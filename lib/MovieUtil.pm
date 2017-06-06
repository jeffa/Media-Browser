package MovieUtil;
use strict;
use warnings;
use Data::Dumper;
use Exporter 'import';
our @EXPORT_OK = qw(
    canonicalize
    extract_imdb
    get_details
    get_raw_titles
    get_dbh
);

use DBI;
use MongoDB;
use IMDB::Film;
use File::Slurp;
use File::Basename;
use HTML::TableExtract;
use HTML::TokeParser::Simple;
use File::Temp qw( tempfile );
use Encode qw( encode decode );

my @prune = get_prune();

chomp( my $text = read_file( '.secret' ) );
my @creds = split /\s+/, $text;

sub get_dbh {
    my $dbh = DBI->connect(
        'DBI:mysql:database=media', @creds,
        { RaiseError => 1 },
    );
    $dbh->{mysql_enable_utf8} = 1;
    return $dbh;
}

sub get_raw_titles {
    return MongoDB
        ->connect( 'mongodb://localhost' )
        ->get_database( 'movies' )
        ->get_collection( 'raw_titles' )
    ;
}

sub get_details {
    my $movie    = shift;
    return {} unless $movie->{content} and $movie->{fullcredits};

    my $imdb = build_imdb( $movie->{content}, $movie->{imdb_id} );
    my @genres = map { s/^\s*//; s/\s*$//; $_ } @{ $imdb->genres };

    my @directors       = extract_names( $movie->{fullcredits}, 0 );
    my @writers         = extract_names( $movie->{fullcredits}, 1 );
    my ($title, @aka)   = extract_titles( $movie->{releaseinfo} );

    return {
        title       => $title,
        kind        => $imdb->kind,
        year        => $imdb->year,
        cover       => $imdb->cover,
        tagline     => $imdb->tagline,
        story       => $imdb->storyline,
        duration    => [ map { $_ eq '|' ? () : $_ } $imdb->duration ],
        country     => $imdb->country,
        language    => $imdb->language,
        aka         => [ @aka ],
        mpaa        => $imdb->mpaa_info,
        ratio       => $imdb->aspect_ratio,

        directors   => [ @directors ],
        writers     => [ @writers ],
        genres      => [ @genres ],
    };
}

sub extract_titles {
    my $html = shift;
    my $toke = HTML::TokeParser::Simple->new( \$html );

    my @titles;
    while ( my $token = $toke->get_token ) {
        if ( $token->is_start_tag( 'h3' ) and $token->get_attr( 'itemprop' ) eq 'name' ) {
            $token = $toke->get_token for 1 .. 3;
            push @titles, $token->as_is;
            last;
        }
    }

    my $te = HTML::TableExtract->new( attribs => { id => 'akas' } );
    $te->parse( $html );
    (my $table) = $te->tables;
    return @titles unless $table;

    for my $row ($table->rows) {
        push @titles, { country => $row->[0], title => $row->[1] };
    }

    return @titles;
}

sub extract_names {
    my ($html,$count) = @_;

    my $te = HTML::TableExtract->new(
        attribs => { class => 'simpleTable simpleCreditsTable' },
        count   => $count,
        keep_html => 1,
    );
    $te->parse( $html );
    (my $table) = $te->tables;
    return unless $table;

    my @names;
    for (@{ ($table->columns)[0] }) {
        my ($id,$name) = $_ =~ m|/(nm\d{7})[^>]+>\s*([^<]+)<|;
        next unless $id and $name;
        $name =~ s/\s+$//;
        push @names, { id => $id, name => $name };
    }

    return @names;
}

sub build_imdb {
    my ($html,$filename) = @_;

    my ($fh, $tmpname) = tempfile( $filename . 'XXXX', suffix => '.html', dir => '/tmp', unlink => 0 );
    binmode $fh, ":utf8";
    print $fh $html;

    my $parsed = IMDB::Film->new( crit => $tmpname );
    # IMDB::Film is failing to scrape languages and country
    # we'll just get them from the main page ourselves xD
    my $toke = HTML::TokeParser::Simple->new( $tmpname );
    while ( my $token = $toke->get_token ) {
        if ( $token->is_start_tag( 'h4' ) ) {
            my $label = $toke->get_token->as_is;
            if ($label eq 'Country:') {
                $parsed->{_country} = _extract_things( $toke );
            } elsif ($label eq 'Language:') {
                $parsed->{_language} = _extract_things( $toke );
            }
        }
    }

    close $fh;
    unlink $tmpname or warn "$tmpname persisted: $!\n";
    return $parsed;
}

sub _extract_things {
    my $toke = shift;
    my $tag  = shift || 'a';
    my @things;
    while ( my $token = $toke->get_token ) {
        last if $token->is_end_tag( 'div' );
        if ( $token->is_start_tag( $tag ) ) {
            push @things, $toke->get_token->as_is;
        }
    }
    return [@things];
}

sub canonicalize {
    my $term = shift;

    $term = basename( $term, qw( .avi .mkv .mp4 .divx .m4v ) );
    $term =~ s/_/ /g;

    $term =~ s/\s(?:HD|4-3|VHS|480p|720p|1080p)$//;
    $term =~ s/\spt(?:1|2|3)$//;
    $term =~ s/\sPart\s?(?:1|2)$//;
    $term =~ s/\.cd(?:1|2)$//;
    $term =~ s/\srecut(?:1|2)$//;
    $term =~ s/\s_?(?:1|2)$//;
    $term =~ s/\s1080p\.srt$//;
    $term =~ s/\sBlack\sand\sWhite$//;
    $term =~ s/\s\(despecialized\)$//;
    $term =~ s/\sworkprint$//;
    $term =~ s/\s-\sRifftrax$//;
    $term =~ s/\s-\sAlternative\sEdition\sV\.2//;
    $term =~ s/\s\(Theatrical\sRelease\)//;
    $term =~ s/^Disneys\s//;

    $term =~ s/\sPart\s(?:One|Two)//;
    $term =~ s/\saka\s[^0-9]+/ /;

    $term =~ s/^($_)\s*\-?\s*// for @prune;

    return $term;
}

sub extract_imdb {
    my $url = shift;
    (my $id) = $url =~ /\/(tt\d{7})\/?/;
    return $id;
}

sub get_prune {
    return qw(
        B1 B2 B3 B4 B5
        CoN1 CoN2 CoN3 
        FT1 FT2 FT3 FT4 FT5 FT6 FT7 FT8 FT9 
        HP1 HP2 HP3 HP4 HP5 HP6 HP7 
        JB01 JB02 JB03 JB04 JB05 JB06 JB07 JB08 JB09 JB10 JB11 JB12 JB13 JB14 JB15 JB16 JB17 JB18 JB19 JB20
        JW1 JW2 JW3
        LotR1 LotR2 LotR3 LotR4 LotR5 LotR6
        M1 M2 M3
        NES1 NES2 NES3 NES4 NES5 NES6 NES7 
        ST01 ST02 ST03 ST04 ST05 ST06 ST07 ST08 ST09 ST10 ST11 ST12 ST13 
        StWr1 StWr2 StWr3 StWr4 StWr5 StWr6 StWr78 StWr7
    );
}


1;
