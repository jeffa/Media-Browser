#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;

use JSON;
use MP4::Info;
use XML::Simple;
use File::Find::Rule;

GetOptions (
    'dir=s'     => \my $dir,
    'file=s'    => \my @file,
    'limit=i'   => \my $limit,
    'help'      => \my $help,
    'man'       => \my $man,
);

pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;

my @files;
if ($dir) {
    pod2usage( 'dir must be valid path' ) unless -d $dir;

    @files = File::Find::Rule
        ->file()
        ->name( '*.avi', '*.mp4', '*.mkv', '*.divx', '*.m4v' )
        ->in( $dir )
    ;
} elsif (@file) {
    @files = ( @file ); 
}

for my $file (@files) {
    my %rel;
    my $xml = `mediainfo -f --Output=XML "$file"`;

    my $media;
    eval { $media = XMLin( $xml, ForceArray => [] ) };
    if ($@) {
        warn "Could not parse $file: $@\n";
        next;
    }

    my ($header,$video,$audio) = @{ $media->{File}{track} };

    $rel{duration}          = $header->{Duration}[4];
    $rel{file_name}         = $header->{Complete_name};
    $rel{file_size}         = $header->{File_size}[0];
    $rel{display_size}      = $header->{File_size}[1];

    $rel{source}            = $video->{Movie_name} || $video->{Title} || $video->{Comment};
    $rel{frame_rate}        = $video->{Frame_rate}[0];
    $rel{bit_rate}          = $video->{Bit_rate}[0];
    $rel{codec}             = $video->{Codec}[0];
    $rel{width}             = $video->{Width}[0];
    $rel{height}            = $video->{Height}[0];
    $rel{ratio}             = $video->{Display_aspect_ratio}[1];
    $rel{scan_type}         = $video->{Scan_type}[0];
    $rel{format}            = $video->{Format};
    $rel{version}           = $video->{Encoded_Library_Version};

    $rel{audio_format}      = $audio->{Format};
    $rel{audio_sample_rate} = $audio->{Sampling_rate}[0];
    $rel{audio_bit_rate}    = $audio->{Bit_rate}[0];
    $rel{audio_bit_mode}    = $audio->{Bit_rate_mode}[0];
    $rel{audio_channels}    = $audio->{Channel_s_}[0];

    #print encode_json( \%rel ), $/;
    print Dumper \%rel;
}

__END__
=head1 NAME

extract-file-info - fetch IMDb page(s)

=head1 SYNOPSIS

./extract-file-info --dir=/Volumes/MOVIES

 Options:
   --dir        path to find movies from 
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--dir>

Path to find movies from

  --dir=/Volumes/MOVIES/

=item B<--file>

Extract info this file (or these files)

  --file=/Volumes/MOVIES/foo.mp4

=back
