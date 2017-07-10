package Media::Info::Mediainfo;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Capture::Tiny qw(capture);
use IPC::System::Options 'system', -log=>1;
use Perinci::Sub::Util qw(err);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       get_media_info
               );

our %SPEC;

$SPEC{get_media_info} = {
    v => 1.1,
    summary => 'Return information on media file/URL, using the `mediainfo` program',
    args => {
        media => {
            summary => 'Media file',
            schema  => 'str*',
            pos     => 0,
            req     => 1,
        },
    },
    deps => {
        prog => 'mediainfo',
    },
};
sub get_media_info {
    require File::Which;
    no warnings 'numeric';

    my %args = @_;

    File::Which::which("mediainfo")
          or return err(412, "Can't find mediainfo in PATH");
    my $media = $args{media} or return err(400, "Please specify media");

    # make sure user can't sneak in cmdline options to ffmpeg
    $media = "./$media" if $media =~ /\A-/;

    my ($stdout, $stderr, $exit) = capture {
        local $ENV{LANG} = "C";
        system("mediainfo", "--Language=raw", $media);
    };

    return err(500, "Can't execute mediainfo successfully ($exit)") if $exit;

    my $info = {};
    my $cur_section;
    for my $line (split /^/, $stdout) {
        next unless $line =~ /\S/;
        chomp $line;
        unless ($line =~ /:/) {
            $cur_section = $line;
            next;
        }
        my ($key, $val) = $line =~ /(\S+.*?)\s*:\s*(\S.*)/ or next;
        #say "D:section=<$cur_section> key=<$key> val=<$val>";
        if ($cur_section eq 'General') {
            $info->{duration} = $1 * 3600 + $2 * 60 + $3 if $key eq 'DURATION' && $val =~ /(\d+):(\d+):(\d+\.\d+)/;
        } elsif ($cur_section eq 'Video') {
            $info->{video_format} = $val if $key eq 'Format';
            $info->{video_width}  = $val+0 if $key eq 'Width/String';
            $info->{video_height} = $val+0 if $key eq 'Height/String';
            $info->{video_aspect} = $1/$2 if $key eq 'DisplayAspectRatio/String' && $val =~ /(\d+):(\d+)/;
            $info->{video_fps} = $val+0 if $key eq 'FrameRate/String';
            # XXX video_bitrate
        } elsif ($cur_section =~ /^Audio/) {
            # XXX handle multiple audio streams
            $info->{audio_format} //= $val if $key eq 'Format';
            $info->{audio_rate} //= $1*1000 if $key eq 'SamplingRate/String' && $val =~ /(\d+(?:\.\d+)?) KHz/;
            # XXX audio_bitrate
        }
    }

    [200, "OK", $info, {"func.raw_output"=>$stdout}];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

Use directly:

 use Media::Info::Mediainfo qw(get_media_info);
 my $res = get_media_info(media => '/home/steven/celine.avi');

or use via L<Media::Info>.

Sample result:

 [
   200,
   "OK",
   {
     audio_bitrate => 128000,
     audio_format  => "aac",
     audio_rate    => 44100,
     duration      => 2081.25,
   },
   {
     "func.raw_output" => "General\nComplete name   ...",
   },
 ]


=head1 SEE ALSO

L<Media::Info>

L<mediainfo> program (including CLI, GUI, and shared library),
L<http://mediaarea.net/en/MediaInfo>

=cut
