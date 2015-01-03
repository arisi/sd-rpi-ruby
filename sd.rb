#!/usr/bin/env ruby
#encoding: UTF-8

require 'pp'
require 'time'
require 'pi_piper'
include PiPiper

def init hash
  pp hash
  @options=hash
  @cs =PiPiper::Pin.new(:pin => hash[:cs], :direction => :out)
  @do =PiPiper::Pin.new(:pin => hash[:do], :direction => :out)
  @clk=PiPiper::Pin.new(:pin => hash[:clk],:direction => :out)
  @di =PiPiper::Pin.new(:pin => hash[:di], :direction => :in,:pull => :down)
  @cs.on
  @clk.off
  @do.off
  @SPI_CLOCK=2500000
end

options={}
options[:do] = 10 if not options[:do]
options[:di] = 9 if not options[:di]

options[:clk]= 11 if not options[:clk]
options[:cs] = 22 if not options[:cs]

init options
$blklen=512

def outbytes c,l,retlen=1
  ret=[]
  data=[]
  cmd_data=[]
  @cs.off
  PiPiper::Spi.begin do
    clock(2500000)
    l.each do |b|
      cmd_data << write(b)
    end
    write(0xff)
    retlen.times do
      data << write(0xff)
    end
    if c and c[:data] == :busy
      tries=0
      while (start=write(0xff))==0 do
        if tries>10000
          puts "Error: busy stuck (#{c},#{l})"
          break
        end
        tries+=1
        sleep 0.01
      end
      #puts "took #{tries} to unbusy"
    elsif c and c[:data] == :read
      data=[]
      tries=0
      while (start=write(0xff))!=0xfe do
        if tries>1000
          puts "Error: data read stuck with [0x#{start.to_s(16)}] (#{c},#{l}) tried #{tries}"
          break
        end
        tries+=1
        sleep 0.001
      end
      if start==0xfe
        if c[:datalen]
          c[:datalen].times do
            data << write(0xff)
          end
        else
          ($blklen).times do
            data << write(0xff)
          end
        end
        write(0xff)
        write(0xff)
      end
    end
  end
  @cs.on
  data
end

Cmds={
  send_op_cond: {op: 1,  retlen: 1},
  send_csd:     {op: 9,  retlen: 1, data: :read, datalen:18},
  #send_csd:     {op: 9,  retlen: 22},
  send_cid:     {op: 10, retlen: 1, data: :read, datalen:18},
  send_status:  {op: 13, retlen: 2},
  set_blocklen: {op: 16, retlen: 1},
  read_single_block:  {op: 17, retlen: 1, data: :read},
  write_block:  {op: 24, retlen: 1, data: :write},
  erase_start:  {op: 32, retlen: 1},
  erase_end:    {op: 33, retlen: 1},
  erase:        {op: 38, retlen: 1, data: :busy},
  send_scr:     {op: 51, retlen: 1, data: :read, datalen:10},
  app_cmd:      {op: 55, retlen: 1},
  read_ocr:     {op: 58, retlen: 5},
}
def cmd cmd,val=0,retlen=nil
  if not Cmds[cmd]
    puts "Error: Unknown Command to SD: #{cmd}"
  end
  c=Cmds[cmd][:op]
  retlen=Cmds[cmd][:retlen] if not retlen
  l=[c|0x40]
  l+=[val].pack("N").unpack("CCCC")
  l<<1
  data=outbytes Cmds[cmd],l,retlen
  if @options[:verbose]
    printf("%20.20s (%2d %08X): ",cmd,c,val)
    data.each_with_index do |b,i|
      printf("%02X ",b)# if i<30
    end
    puts ""
  end
  data
end

def hdump l
  print "["
  l.each do |b|
    printf "%02X ", b
  end
  print "]\n"
end

def bdump l
  print "["
  l.each do |b|
    printf "%08d ", b.to_s(2)
  end
  print "]\n"
end

def pickbits l,so,eo
  sz=l.size*8
  #puts "size: #{sz}"
  b=[]
  s=sz-so-1
  e=sz-eo-1
  (s .. e).each do |bit|
    byte=bit/8
    oset=bit%8
    bval= 1<<oset
    v=(l[byte]&bval)==bval
    if v
      b=[1]+b
    else
      b=[0]+b
    end
    #puts "bit=#{bit} byte=#{byte} oset=#{oset} bval=#{bval},v=#{v}"
  end
  val=0
  b.each do |bit|
    val*=2
    if bit==1
      val|=1
    end
  end
  printf "%d:%d 0x%X (%d)\n",so,eo,val,val
  val
end

def ident
  info={}
  ret=cmd :send_cid
  if ret and ret!=[]
    info=info.merge({
      mid: ret[0].to_s(16),
      oem:ret[1...1+2].pack("c*"),
      pnm:ret[3...3+5].pack("c*"),
      rev: ret[7],
      serno: ret[8...8+5],
      date: sprintf("%d/%d",2000+ret[14]/0x10,ret[14]&0xf),
    })
  end
  ret=cmd :send_csd
  if ret and ret!=[]
    bdump ret
    hdump ret[5..7]
    pickbits ret[0..-3],119,112
    pickbits ret[0..-3],103,96
    pickbits ret[0..-3],95,84
    info[:block_size]=2**(pickbits ret[0..-3],83,80)
    info[:block_count]=pickbits ret[0..-3],73,62
    info[:block_mult]=2**(2+pickbits(ret[0..-3],49,47))
    pickbits ret[0..-3],45,39
    pickbits ret[0..-3],25,22
    info[:capacity]=info[:block_count]*524288
    info[:capacity_gb]=sprintf("%.1f",info[:block_count]*524288/(1000.0**3.0))
  end
  info
end

def boot
  loop do
    ret=outbytes nil,[0x40, 0, 0, 0, 0,0x95]
    if ret[0]==0x01
      break
    end
  end
  loop do
    ret=cmd :send_op_cond
    if ret[0]==0x00
      break
    end
  end
end
#00 80 FF 80 00
boot

def init
  tries=0
  ret=false
  loop do
    ret=cmd :read_ocr
    if ret==[0,0,0,0,0]
      if tries>10
        puts "Error: Cannot Init SD Card"
        ret=false
        break
      end
      boot
      sleep 0.01
    else
      break
    end
    tries+=1
  end
  ret
end


if not init
  exit -1
else
  pp ident
  cmd :set_blocklen,$blklen
  cmd :app_cmd
  cmd :send_scr
end
#cmd :send_status

def erase from=0,till=0
  return  if till<=from
  cmd :erase_start,from*$blklen
  cmd :erase_end,till*$blklen
  cmd :erase
end
def write addr=0,data=[]
  return if not data or data==[]
  buf=[0xfe]
  buf+=data
  buf << 0 #crc 2 bytes
  buf << 0
  buf << 0 #this will shift data response

  cmd :write_block,addr
  outbytes({data: :busy},buf)
end
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

