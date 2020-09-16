require 'benchmark'

RSpec.describe MB::Sound::FFMPEGInput do
  describe '.parse_info' do
    let(:info) {
      MB::Sound::FFMPEGInput.parse_info('sounds/sine/sine_100_1s_mono.flac')
    }

    let(:info_multi) {
      MB::Sound::FFMPEGInput.parse_info('spec/test_data/two_audio_streams.mkv')
    }

    it 'can read stream info from a .flac sound file' do
      expect(info).to be_a(Hash)
      expect(info[:streams][0][:duration_ts]).to eq(48000)
      expect(info[:streams][0][:duration].round(4)).to eq(1)
      expect(info[:streams][0][:channels]).to eq(1)
    end

    it 'can read format info from a .flac sound file' do
      expect(info[:format][:tags][:title]).to eq('Sine 100Hz 1s mono')
    end

    it 'can read info about multiple audio streams' do
      expect(info[:streams].length).to eq(1)
      expect(info_multi[:streams].length).to eq(2)
    end
  end

  let(:input) {
    MB::Sound::FFMPEGInput.new('sounds/sine/sine_100_1s_mono.flac')
  }

  let(:input_2ch) {
    MB::Sound::FFMPEGInput.new('sounds/sine/sine_100_1s_mono.flac', channels: 2)
  }

  let(:input_441) {
    MB::Sound::FFMPEGInput.new('sounds/sine/sine_100_1s_mono.flac', resample: 44100)
  }

  let(:input_multi_0) {
    MB::Sound::FFMPEGInput.new('spec/test_data/two_audio_streams.mkv', stream_idx: 0)
  }

  let(:input_multi_1) {
    MB::Sound::FFMPEGInput.new('spec/test_data/two_audio_streams.mkv', stream_idx: 1)
  }

  describe '#initialize' do
    it 'can load and parse info from a .flac sound' do
      expect(input.frames).to eq(48000)
      expect(input.rate).to eq(48000)
      expect(input.channels).to eq(1)
      expect(input.info[:tags][:title]).to eq('Sine 100Hz 1s mono')

      input.read(100000) # allow ffmpeg to empty its buffer
      expect(input.close.success?).to eq(true)
    end

    it 'can change the number of channels' do
      expect(input_2ch.channels).to eq(2)
      expect(input_2ch.read(100000).size).to eq(2)
      expect(input_2ch.close.success?).to eq(true)
    end

    it 'can change the sample rate' do
      expect(input_441.frames).to eq(44100)
      expect(input_441.rate).to eq(44100)
      expect(input_441.read(100000)[0].size).to eq(44100)
      expect(input_441.close.success?).to eq(true)
    end

    it 'can load a second audio stream' do
      expect(input_multi_0.rate).to eq(48000)
      expect(input_multi_0.channels).to eq(1)
      expect(input_multi_1.rate).to eq(44100)
      expect(input_multi_1.channels).to eq(2)

      expect(input_multi_0.read(100000)[0].size).to eq(48000)
      expect(input_multi_1.read(100000)[0].size).to eq(44100)

      expect(input_multi_0.close.success?).to eq(true)
      expect(input_multi_1.close.success?).to eq(true)
    end
  end

  describe '#read' do
    it 'can read all data at once' do
      d1 = input.read(100000)
      expect(d1.length).to eq(input.channels)
      expect(d1[0].length).to eq(input.frames)

      expect(input.close.success?).to eq(true)
    end

    it 'can read data in chunks' do
      d1 = input.read(5000)[0]
      d2 = input.read(input.frames - 5000)[0]
      expect(d1.length).to eq(5000)
      expect(d2.length).to eq(43000)

      # Compare to the stereo version (compensating for pan law)
      dref = input_2ch.read(input_2ch.frames)[0]
      d3 = d1.concatenate(d2)
      scale = d3.max / dref.max
      expect(d1.concatenate(d2).map { |v| v.round(3) }).to eq(dref.map { |v| (v * scale).round(3) })

      expect(input.close.success?).to eq(true)
    end

    it 'reads data correctly' do
      d = input.read(input.frames)[0]

      # Check for statistical characteristics of a sine wave
      expect(d.sum.abs).to be < 0.01
      expect(d.median).to be < 0.1
      expect(d.max).to be_between(0.4, 1.0).inclusive
      expect(d.min).to be_between(-1.0, -0.4).inclusive

      expect(input.close.success?).to eq(true)
    end

    it 'reads the correct input stream' do
      d1 = input_multi_0.read(48000)
      d2 = input_multi_1.read(48000)

      expect(d1.length).to eq(1)
      expect(d2.length).to eq(2)
      expect(d1[0].length).to eq(48000)
      expect(d2[0].length).to eq(44100)

      expect(input_multi_0.close.success?).to eq(true)
      expect(input_multi_1.close.success?).to eq(true)
    end
  end

  describe '#close' do
    it 'can close a file before finishing reading' do
      result = nil
      delay = Benchmark.realtime do
        expect { result = input.close }.not_to raise_exception
      end

      expect(delay).to be < 1
      expect(result).to be_a(Process::Status)

      expect { input.read(1) }.to raise_exception(IOError)
    end
  end
end
