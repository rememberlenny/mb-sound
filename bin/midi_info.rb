#!/usr/bin/env ruby
# Displays number of events from each channel, and other info about a MIDI
# file.
#
# Usage: $0 midi_file.mid

require 'bundler/setup'

require 'mb-sound'

if ARGV.include?('--help') || ARGV.length != 1
  puts MB::U.read_header_comment.join.gsub('$0', $0)
  exit 1
end

f = MB::Sound::MIDI::MIDIFile.new(ARGV[0], merge_tracks: false)

title = f.seq.name

NAME_MAP = {
  index: '#',
  name: 'Name',
  instrument: 'Inst.',
  channel_mask: 'Ch. mask',
  event_channels: 'Event ch.',
  channel: 'Ch.',
  num_events: 'Events',
  num_notes: 'Notes',
}.freeze

track_info = f.tracks.reduce({}) { |h, t|
  t.each do |k, v|
    kname = NAME_MAP[k] || k.to_s
    h[kname] ||= []
    h[kname] << v
  end

  h
}

msg = "#{File.basename(f.filename)}: \e[1m#{title}\e[0m"
len = MB::U.remove_ansi(msg).length
puts '', msg, '-' * len, ''

puts MB::U.table(track_info, variable_width: true)
