#!/usr/bin/env ruby

####################################################
# NOOKIFY
####################################################
# This utility prepares scanned PDFs for your nook
# by eliminating all margins and optionally split-
# ting pages in two and rotating them so that they
# can be read in the horizontal direction on your
# e-reader. It was written for use on my B&N Nook
# but can be used for pretty much any e-reader with
# native PDF support. This script depends on:
#
# - Unix environment (linux, BSD, OSX etc.)
# - Ruby, rubygems and progressbar gem
# - Imagemagick convert binary somewhere in your
#   path
# - pdftk binary somewhere in your path
####################################################

require 'optparse'
require 'ostruct'
require 'ftools'
require 'open3'

require 'rubygems'
require 'progressbar'

# constants
APP_NAME = File.basename(__FILE__)
WORKING_DIR = "/tmp/.tmp_#{APP_NAME}" 

####################################################
# parse command-line options
####################################################
options = OpenStruct.new
optparse = OptionParser.new do |opts|
  # defaults
  options.overlap = 50
  options.density = 300
  
  opts.banner = "Usage: #{__FILE__} [options] <pdf_file>"
  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
  opts.on('-s', '--split', 'Split page in half and rotate halves for easier reading') do
    options.split = true
  end
  opts.on('-o', '--overlap [PIXELS]',
    "How much to overlap each half when splitting " +
    "(defaults to #{options.overlap} or about " +
    "#{sprintf('%.02f', options.overlap / (options.density * 1.0))} inch)") do |overlap|
    options.overlap = overlap
  end
end
optparse.parse!

if ARGV.empty?
  puts optparse
  exit
end

input_file = ARGV.shift
unless File.exist?(input_file)
  puts "Can't locate file #{input_file}"
  puts optparse
  exit
end

Dir.mkdir(WORKING_DIR)
basename = File.basename(input_file)
File.copy(input_file, "#{WORKING_DIR}/#{basename}")
original_dir = Dir.pwd
Dir.chdir(WORKING_DIR)
print "Splitting PDF into separate pages..."
STDOUT.flush
`pdftk "#{basename}" burst`
print "\rTrimming each page..."
STDOUT.flush
pages = Dir['pg_*.pdf']
progressbar = ProgressBar.new('Trimming', pages.size)
pages.each do |page|
  cmd = "convert -density #{options.density} -virtual-pixel edge -blur 0x10 -fuzz 15% -trim #{page} info:"
  stem = File.basename(page, '.pdf')
  Open3.popen3(cmd) do |stdin, stdout, stderr|
    resolution, trim_offset = stdout.read.strip.match(/(\d+x\d+) \d+x\d+\+(\d+\+\d+)/).to_a[1..-1]
    width, height = resolution.split('x').map {|n| n.to_i }
    cmd = "convert -density #{options.density} -crop #{resolution}+#{trim_offset} +repage #{page} #{stem}.png"
    Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
    if options.split
      if height > (options.density * 3)
        cmd = "convert -crop 1x2+#{options.overlap}+#{options.overlap}@ +repage +adjoin #{stem}.png #{stem}-%d.png"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
        cmd = "convert -rotate -90 #{stem}-0.png #{stem}-0-rotated.png"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
        cmd = "convert -rotate -90 #{stem}-1.png #{stem}-1-rotated.png"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
        cmd = "convert #{stem}-0-rotated.png #{stem}_0_final.pdf"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
        cmd = "convert #{stem}-1-rotated.png +repage #{stem}_1_final.pdf"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
      else
        cmd = "convert -rotate -90 #{stem}.png #{stem}_rotated.png"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
        cmd = "convert #{stem}_rotated.png #{stem}_final.pdf"
        Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
      end
    else
      cmd = "convert #{stem}.png #{stem}_final.pdf"
      Open3.popen3(cmd) {|stdin, stdout, stderr| stdout.read; stderr.read }
    end
  end
  progressbar.inc
end
progressbar.finish
print "\rConcatenating trimmed pages..."
STDOUT.flush
`pdftk *_final.pdf cat output "#{original_dir}/#{File.basename(input_file, '.pdf')}_trimmed.pdf"`
Dir.chdir(original_dir)
`rm -rf #{WORKING_DIR}`