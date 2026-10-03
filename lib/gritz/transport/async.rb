# frozen_string_literal: true

require "set" # rubocop:disable Lint/RedundantRequireStatement -- required by Ruby 3.3
require "socket"
require "async"
require_relative "async/bridge"
require_relative "async/server"

module Gritz
  module Transport
    # Runs RPC controllers in fibers without the grpc C extension.
    # @api public
    class Async
      def self.capabilities = Set[:unary, :client_streaming, :server_streaming, :bidi, :reuseport, :inherited_fd, :fiber].freeze

      def initialize(config:, dispatcher:, logger:)
        @config = config
        @dispatcher = dispatcher
        @logger = logger
        @lock = Mutex.new
        @inflight = {}.compare_by_identity
        @requests_total = @rejected_total = 0
      end

      # The caller retains ownership of an inherited socket; only its duplicate is closed.
      # @return [Integer] the selected TCP port
      def bind(listener_spec = @config.bind)
        raise ArgumentError, "transport is already bound" if @listener
        raise ArgumentError, "at least one controller must be registered" if @dispatcher.router.routes.empty?
        raise ConfigurationError, "Async reflection is not supported" if @config.reflection
        raise ConfigurationError, "Async TLS is not supported" unless @config.tls.empty?

        %i[max_connection_age max_connection_age_grace keepalive_time keepalive_permit_without_calls].each do |setting|
          unless @config.public_send(setting) == Configuration::DEFAULTS.fetch(setting)
            raise ConfigurationError, "#{setting} is only supported by the Native adapter"
          end
        end

        if listener_spec.respond_to?(:accept)
          @listener = listener_spec.dup
        else
          @listener = Supervisor::Listener.bind(listener_spec, reuseport: @config.listener_strategy == :reuseport)
        end
        @listener.local_address.ip_port
      end

      def start
        raise ArgumentError, "transport is stopped" if @stopped
        raise ArgumentError, "bind must be called before start" unless @listener
        raise ArgumentError, "transport is already started" if @thread

        @control_r, @control_w = IO.pipe
        ready = Queue.new
        @thread = Thread.new do
          Async do |root|
            bridge = Bridge.new(self, @dispatcher.router.routes, config: @config, logger: @logger)
            @server = Server.new(bridge, @logger)
            acceptor = root.async do
              loop do
                peer, address = @listener.accept
                root.async(peer, address) do |_task, client, remote|
                  @server.accept(client, remote)
                ensure
                  client.close unless client.closed?
                end
              end
            end
            ready << true
            @control_r.read(1)
            acceptor.stop
            @listener.close
            @server.stop(deadline: @stop_deadline)
          ensure
            root.children.to_a.each(&:stop)
          end
        rescue StandardError => e
          ready << e
          raise
        end
        result = ready.pop(timeout: 5)
        raise(result || "Async server did not start within 5 seconds") unless result == true

        self
      end

      def running? = @thread&.alive? && !@stopped
      def wait = @thread&.value

      def stop(deadline:)
        drain!
        return if @stopped

        @stopped = true
        @stop_deadline = deadline
        if @thread&.alive?
          @control_w.write(".")
          wait
        end
      ensure
        @listener&.close unless @listener&.closed?
        @control_r&.close unless @control_r&.closed?
        @control_w&.close unless @control_w&.closed?
      end

      def kill = stop(deadline: Time.now)

      def drain!
        @draining = true
        self
      end

      def update_health(ready:, checks: {}) = ready && checks.values.all? && !@draining

      def refresh_health
        checks = @config.health_checks.transform_values do |check|
          check.call ? true : false
        rescue StandardError
          false
        end
        update_health(ready: running?, checks:)
      end

      def stats
        @lock.synchronize do
          oldest = @inflight.values.min
          { inflight: @inflight.size, busy: @inflight.size, capacity: @config.threads + @config.max_waiting_requests,
            rejected_total: @rejected_total, requests_total: @requests_total,
            oldest_inflight_age: oldest ? Process.clock_gettime(Process::CLOCK_MONOTONIC) - oldest : 0 }
        end
      end

      # @api private
      def dispatch(call)
        admitted = @lock.synchronize do
          if @inflight.size >= @config.threads + @config.max_waiting_requests
            @rejected_total += 1
            false
          else
            @inflight[call] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @requests_total += 1
            true
          end
        end
        raise Errors::ResourceExhausted, "Async concurrency limit reached" unless admitted

        result = @dispatcher.call(call)
        call.write(result) unless call.method_descriptor.server_streaming?
      ensure
        @lock.synchronize { @inflight.delete(call) } if admitted
      end
    end
  end
end
