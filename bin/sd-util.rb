#!/usr/bin/env ruby
#encoding: UTF-8

require 'optparse'
require 'yaml'

lib="sd"
if File.file? "./lib/#{lib}.rb"
  require "./lib/#{lib}.rb"
  puts "using local #{lib}"
  local=true
else
  require lib
end


options={}


$sd=Sd.new options

if not $sd.init
  exit -1
else
  pp $sd.ident
end
#cmd :send_status

b=4

if false
  tb=1000
  mul=5000
  erase 0,tb*mul

  rers=wers=0
  start=Time.now.to_f
  (0..tb).each do |j|
    start2=Time.now.to_f
    buf=[]
    $blklen.times do |i|
      buf << ((i+j)&0xff)
    end
    a=$blklen*j*mul
    printf "%08X (%.3fMb) [%d]",a,a/1000000.0,j*mul
    write a,buf
    d=cmd :read_single_block,a
    now=Time.now.to_f
    if buf==d
      printf "OK %.2f %.2f\n",now-start,now-start2
    else
      puts "ER"
      wers+=1
    end
  end
  puts "Verify:"
  start=Time.now.to_f
  (0..tb).each do |j|
    start2=Time.now.to_f
    buf=[]
    $blklen.times do |i|
      buf << ((i+j)&0xff)
    end
    a=$blklen*j*mul
    printf "%08X ",a
    d=cmd :read_single_block,a
    now=Time.now.to_f
    if buf==d
      printf "OK %.2f %.2f\n",now-start,now-start2
    else
      puts "ER"
      rers+=1
    end
  end
  puts "Write Errs: #{wers}, Read Errs: #{rers}"
end

