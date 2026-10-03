# frozen_string_literal: true

require "spec_helper"
require "zlib"

RSpec.describe Gritz::Transport::Async::Input do
  def input(payload, compressed: false, encoding: nil, limit: 1024)
    body = double("HTTP body")
    allow(body).to receive(:read).and_return([compressed ? 1 : 0, payload.bytesize].pack("CN") + payload, nil)
    described_class.new(body, limit:, encoding:)
  end

  it "rejects a huge declared frame before requesting payload bytes" do
    body = double("HTTP body")
    expect(body).to receive(:read).once.and_return([0, 0xffff_ffff].pack("CN"))
    reader = described_class.new(body, limit: 1024)
    expect { reader.read }.to raise_error(Gritz::Errors::ResourceExhausted)
  end

  it "reads bounded gzip and deflate frames" do
    { "gzip" => Zlib.gzip("hello"), "deflate" => Zlib::Deflate.deflate("hello") }.each do |encoding, payload|
      expect(input(payload, compressed: true, encoding:).read).to eq("hello")
    end
  end

  it "rejects invalid and truncated compressed frames" do
    ["bad gzip", Zlib.gzip("hello")[0...-5]].each do |payload|
      expect { input(payload, compressed: true, encoding: "gzip").read }.to raise_error(Gritz::Errors::InvalidArgument)
    end
  end
end
