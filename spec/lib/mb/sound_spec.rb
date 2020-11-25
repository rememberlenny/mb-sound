require 'fileutils'

RSpec.describe MB::Sound do
  describe '.read' do
    it 'can read a sound file' do
      a = MB::Sound.read('sounds/sine/sine_100_1s_mono.flac')
      expect(a.length).to eq(1)
      expect(a[0].length).to eq(48000)
      expect(a[0].max).to be_between(0.4, 1.0)
    end

    it 'can read part of a sound file' do
      a = MB::Sound.read('sounds/sine/sine_100_1s_mono.flac', max_frames: 500)
      expect(a.length).to eq(1)
      expect(a[0].length).to eq(500)
    end
  end

  describe '.write' do
    before(:each) do
      FileUtils.mkdir_p('tmp')
      File.unlink('tmp/sound_write_test.flac') rescue nil
      File.unlink('tmp/sound_write_exists.flac') rescue nil
    end

    context 'when writing to a file that does not yet exist' do
      let(:name) { 'tmp/sound_write_test.flac' }
      let(:data) { Numo::SFloat[0, 0.5, -0.5, 0] }

      it 'can write an array of NArrays to a sound file' do
        MB::Sound.write(name, [data], rate: 48000)
        info = MB::Sound::FFMPEGInput.parse_info(name)
        expect(info[:streams][0][:duration_ts]).to eq(4)
      end

      it 'can write a raw NArray to a sound file' do
        MB::Sound.write(name, data, rate: 48000)
        info = MB::Sound::FFMPEGInput.parse_info(name)
        expect(info[:streams][0][:duration_ts]).to eq(4)
      end

      it 'can write a Tone to a sound file' do
        MB::Sound.write(name, 100.hz.for(1), rate: 48000)
        info = MB::Sound::FFMPEGInput.parse_info(name)
        expect(info[:streams][0][:duration_ts]).to eq(48000)
        expect(info[:streams][0][:channels]).to eq(1)
      end

      it 'can write multiple tones to a sound file' do
        MB::Sound.write(name, [100.hz.for(1), 200.hz.for(1)], rate: 48000)
        info = MB::Sound::FFMPEGInput.parse_info(name)
        expect(info[:streams][0][:duration_ts]).to eq(48000)
        expect(info[:streams][0][:channels]).to eq(2)
      end
    end

    context 'when overwrite is false (by default)' do
      it 'raises an error if the sound already exists' do
        name = 'tmp/sound_write_exists.flac'
        FileUtils.touch(name)
        expect {
          MB::Sound.write(name, [Numo::SFloat[0, 0.1, -0.2, 0.3]], rate: 48000)
        }.to raise_error(MB::Sound::FileExistsError)
      end
    end

    context 'when overwrite is true' do
      it 'overwrites an existing file' do
        name = 'tmp/sound_write_exists.flac'

        FileUtils.touch(name)
        expect(File.size(name)).to eq(0)

        MB::Sound.write(name, [Numo::SFloat[0, 0.1, -0.2, 0.3]], rate: 48000, overwrite: true)
        expect(File.size(name)).to be > 0
      end
    end
  end
end
