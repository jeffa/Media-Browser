#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use DBI;

use lib 'lib';
use MovieUtil qw( get_credentials );
 
my $dbh = DBI->connect(
    'DBI:mysql:database=media', get_credentials(),
    { RaiseError => 1 },
);

my $sth = $dbh->selectall_arrayref(
    'select title_id,title from titles',
    {Slice => {}},
);

for my $obj (@$sth) {
    if ($obj->{title} =~ s/^(?:A|An|The|La|Le)\b\s+//) {
        $dbh->do('update titles set sort = ? where title_id = ?', undef, $obj->{title}, $obj->{title_id});
    }
}
