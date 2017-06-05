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
    'id=s'      => \my $title_id,
    'dry-run'   => \my $dry,
    'no-prompt' => \my $no_prompt,
    'help'      => \my $help,
    'man'       => \my $man,
);
pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;
pod2usage( -verbose => 0 ) unless $title_id;

#TODO: lookup title_id if id is actually imdb_id

my $dbh = DBI->connect(
    'DBI:mysql:database=media', get_credentials(),
    { RaiseError => 1 },
);
$dbh->{mysql_enable_utf8} = 1;

=to delete
durations   - from title_id
files       - from title_id
genre_xref  - from title_id
role_xref   - from title_id
genres      - if last genre
select genre_name,count(*) from genre_xref x inner join genres g on x.genre_id=g.genre_id where x.genre_id in( select genre_id from genre_xref where title_id=3228 ) group by x.genre_id;
people      - if last person
roles       - if last role
titles
=end


__END__
=head1 NAME

delete-entry - delete title and all orphaned genre, etc.

=head1 SYNOPSIS

delete-entry --id=XXX --dry-run

 Options:
   --id         title_id or imdb_id
   --dry-run    just show what would have happened
   --no-prompt  do not prompt for deletion confirmation
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--id>

title_id or imdb_id of entry to delete

    --id=3228

    --id=tt0106246

=item B<--dry-run>

Don't deleted any records, just show what would have happened.

=item B<--no-prompt>

Do not prompt for deletion confirmation.

=back
