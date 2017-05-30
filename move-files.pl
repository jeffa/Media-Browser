#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;

use DBI;
use File::Basename;

use lib 'lib';
use MovieUtil qw( get_credentials );

GetOptions (
    'dest=s'    => \my $destination,
    'help'      => \my $help,
    'man'       => \my $man,
);
pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;
pod2usage( 'dest must be valid path' ) unless $destination;
$destination =~ s{$}{/} unless $destination =~ m{/$};

my $dbh = DBI->connect(
    'DBI:mysql:database=media', get_credentials(),
    { RaiseError => 1 },
);
$dbh->{mysql_enable_utf8} = 1;

while (my $line = <STDIN>) {
    my ( $file_id, $filename ) = split /,/, $line;
    die unless $file_id =~ /^\d+$/;
    chomp( $filename );
    my ($name, $path) = fileparse( $filename );

    $dbh->do('
        UPDATE files
        SET file_name = ?
        WHERE file_id = ?
    ', undef, $destination . $name, $file_id );

    printf "%6d: %70s => %s\n", $file_id, $filename, $destination . $name;
}

__END__
=head1 NAME

move-files - fetch IMDb page(s)

=head1 SYNOPSIS

cat DATA.txt | move-files --dest=/Volumes/MOVIES/720p/ 

 Options:
   --dest       destination to move files to
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--dest>

Destination (path) to move files to. Trailing slash will be added if not provided.

  --dest=/Volumes/TV/DOCUMENTARIES

=back
