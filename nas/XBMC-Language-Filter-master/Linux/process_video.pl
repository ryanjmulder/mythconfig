#!/usr/bin/perl

#
#	parse_srt.pl
#	XBMC Language Filter
# 
#	Created by Brock Haymond 9/6/12.
#	Copyright (c) 2012 Brock Haymond <http://brockhaymond.com>.  All rights reserved.
#
# 	Perl script to search a subtitle.srt file for profanity and create an XBMC-compatible EDL file from the results found.
# 	You can call the perl script as follows:
#
#	perl parse_srt.pl "subtitle_file.srt"
#
#	The "subtitle_file.edl" file will be output into the same directory as the original subtitle.srt file.
#

# CONFIG VARIABLES
my $host = "192.168.1.110";
my $db_name = "mythconverg";
my $db_table = "filemarkup";
my $db_user = "mythtv";
my $db_password = "kvg2z0B2";

if($ARGV[$0] eq "") {
	print "Usage: perl process_video.pl [videos root dir] [video dir]\n";
	exit 1;
}

use DBI();
use File::Basename;

my $database = DBI->connect("DBI:mysql:database=$db_name;", $db_user, $db_password );

$a = "/root/subroot/subsubroot/filename";
$b = dirname $a;
$c = basename $a;

my $videosDir = $ARGV[0];
my $videoFile = $ARGV[1];
my $videoFileFullDir = dirname $videoFile;
my $videoFileBaseName = basename $videoFile;
$videoFileBaseName =~ s/\.[^.]*$//;
my $subtitleFileOrigName = "$videoFileFullDir/$videoFileBaseName.srt";
my $subtitlesFile = lc("$videoFileBaseName.srt");
my $subtitlesFile = "$videoFileFullDir/$subtitlesFile";
my $edl = "$videoFileFullDir/$videoFileBaseName.edl";
my $mythFilename = $videoFile ;
$mythFilename =~ s/$videosDir\///;

sub read_file {

    my( $file_name, %args ) = @_ ;

    my $buf ;
    my $buf_ref = $args{'buf_ref'} || \$buf ;

    my $mode = O_RDONLY ;
    $mode |= O_BINARY if $args{'binmode'} ;

    local( *FH ) ;
    sysopen( FH, $file_name, $mode ) or
        print "Can't open $file_name: $!" ;

    my $size_left = -s FH ;

    while( $size_left > 0 ) {

        my $read_cnt = sysread( FH, ${$buf_ref},
            $size_left, length ${$buf_ref} ) ;

        unless( $read_cnt ) {

            print "read error in file $file_name: $!" ;
            last ;
        }

            $size_left -= $read_cnt ;
    }

# handle void context (return scalar by buffer reference)
    return unless defined wantarray ;

# handle list context
    return split m|?<$/|g, ${$buf_ref} if wantarray ;

# handle scalar context
    return ${$buf_ref} ;
}

sub GetSubtitles
{
  if ( -e $subtitleFileOrigName )
  {
    $subtitlesFile = $subtitleFileOrigName
  }
  elsif ( -e $subtitlesFile )
  {
  }
  else
  {
    my $filename = $_[0];
    `subdownloader --cli --video \"$filename\" --rename-subs --lang=eng --quiet`
  }
}

sub GetFPS
{
  my $filename = $_[0];
  my $fps = "0";
  my $mplayerInfo = `mplayer -vo null -ao null -identify -frames 0 "$filename" 2>/dev/null | grep fps`;
  if ($mplayerInfo =~ /.*(\d\d\.\d+) fps/)
  {
    $fps = $1;
  }
  if ( $fps eq "0" )
  {
    print $mplayerInfo;
    exit 1;
  }
  
  return($fps);
}                 


my $fps = GetFPS( $videoFile );

sub AddCut
{
 
  my $cutStartFrame = $fps * ($_[0] - 5);
  my $cutStopFrame = $fps * ($_[1] + 5);

  my $insert = $database->prepare( "INSERT INTO filemarkup (filename, mark, type) VALUES ( ?, ?, ?);" );
  
  $insert->execute( $mythFilename, $cutStartFrame, "4" );
  $insert->execute( $mythFilename, $cutStopFrame, "5" );
}

my $verbose = 1;

if(!open PROFM, "pmatch.txt") {print "Couldn't open profanities match file: $!.\r\n"; exit 1;}
@pmatch = <PROFM>;
chomp(@pmatch);
our %pmatchhash = map { $_ => 1 } @pmatch;
close(PROFM);

if(!open PROFC, "pcontains.txt") {print "Couldn't open profanities contains file: $!.\r\n"; exit 1;}
@pcontains = <PROFC>;
chomp(@pcontains);
close(PROFC);

GetSubtitles( $videoFile );
#if(!open TXT, "$subtitlesFile") {print "Couldn't open file '$subtitlesFile:' $!.\r\n"; exit 1;}
$file = read_file( $subtitlesFile, "binmode" );
if(!open EDL, ">$edl") {print "$!\r\n"; exit 1;}

if($verbose) {print "Processing $subtitlesFile\nWriting to $edl\n";}

my $dbDeleteOld = $database->prepare("DELETE FROM filemarkup WHERE filename=? AND type!='2';");
$dbDeleteOld->execute( $mythFilename );

#undef $/;
#$file = <TXT>;
$file =~ s/\r\n/\n/g;
my @block = split('\n\n', $file);
foreach $block (@block) {
  my @lines = split('\n', $block);
  $block =~ s/^(?:.*\n){1,2}//;
  $block =~ s/,|\.|\?|\!|"|#|:|\<.*?\>|\[(.*|.*\n.*)\]//g;
  $block =~ s/-/ /g;
  $block =~ s/  / /g;
  $found = 0;
  $found |= ($block =~ /.*$_.*/i) foreach (@pcontains);

  my @words = split(' ', $block);
  $found |= exists $pmatchhash{lc($_)} foreach (@words);
  
  if($found) {
#	print "$lines[1]\n$block\n\n";
	$lines[1] =~ s/,/\./g;
    	my @times = split(' --> ', $lines[1]);
	$start = parsetime($times[0]);
	$end = parsetime($times[1]);
	AddCut( $start, $end );
	print EDL "$start     \t$end     \t1\n";
  }
}

if($verbose) {print "Finished parsing $subtitlesFile\n";}

sub parsetime {
  my @time = split(':', $_[0]);
  $time = $time[0]*3600 + $time[1]*60 + $time[2];
  return sprintf "%.2f", $time;
}
	
close(TXT);
close(EDL);

if($verbose) {print "Closed $subtitlesFile\nClosed $edl\n";}
$database->disconnect();
