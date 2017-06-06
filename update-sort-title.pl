#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );
 
my $dbh = get_dbh();

my $sth = $dbh->selectall_arrayref(
    'select title_id,title from titles',
    {Slice => {}},
);

for my $obj (@$sth) {
    if ($obj->{title} =~ s/^(?:A|An|The|La|Le)\b\s+//) {
        warn "change to $obj->{title}\n";
        $dbh->do('update titles set sort = ? where title_id = ?', undef, $obj->{title}, $obj->{title_id});
    }
    if ($obj->{title} =~ s/^\W+\b\s*//) {
        next unless $obj->{title};
        warn "change to $obj->{title}\n";
        $dbh->do('update titles set sort = ? where title_id = ?', undef, $obj->{title}, $obj->{title_id});
    }
}
