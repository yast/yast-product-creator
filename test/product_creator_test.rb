#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "Pkg"
Yast.import "ProductCreator"
Yast.import "AddOnCreator"

describe Yast::ProductCreator do
  subject { Yast::ProductCreator }

  before { Yast::ProductCreator.main }

  describe "#enable_needed_repos" do
    REPOS = {
      1 => { "id" => 1, "enabled" => true },
      2 => { "id" => 2, "enabled" => false }
    }

    before do
      allow(Yast::Pkg).to receive(:SourceGeneralData) { |i| REPOS[i] }
    end

    it "enables disabled repositories" do
      expect(Yast::Pkg).to receive(:SourceSetEnabled).with(2, true)
      expect(Yast::Pkg).to receive(:SourceRefreshNow).with(2)
      expect(Yast::Pkg).to_not receive(:SourceRefreshNow).with(1)
      subject.enable_needed_repos([1, 2])
    end

    it "register repositories to restore their state later" do
      subject.enable_needed_repos([1, 2])
      expect(subject.tmp_enabled).to eq([2])
    end
  end

  describe "#restore_repos_state" do
    before do
      allow(Yast::Pkg).to receive(:SourceGeneralData).and_return("id" => 1, "enabled" => false)
      allow(Yast::Pkg).to receive(:SourceSetEnabled)
      allow(Yast::Pkg).to receive(:SourceRefreshNow)
    end

    context "when some repositories were enabled" do
      let(:source) { 1 }

      before do
        subject.enable_needed_repos([source])
      end

      it "it disables previously enabled repositories" do
        expect(Yast::Pkg).to receive(:SourceSetEnabled).with(source, false)
        subject.restore_repos_state
      end
    end

    context "when no repositories were enabled" do
      it "does not disable any repository" do
        expect(Yast::Pkg).to_not receive(:SourceSetEnabled)
        subject.restore_repos_state
      end
    end
  end
end
