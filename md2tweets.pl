#!/usr/bin/perl

use strict;
use warnings;
use open ':std', ':encoding(UTF-8)';

use URI;
use YAML::XS;
use Path::Tiny;
use Try::Tiny;
use Getopt::Long;

my $VERSION = '0.0.1';

my $RE_DATE_TITLE    = qr/^(\d{4}-\d{2}-\d{2})(.*?)\n(.*)/s;
my $RE_AT_PAGE_TITLE =
    qr/^@([a-z0-9_-]+)\[(.+)\]\s+(\d{4}-\d{2}-\d{2})(!?)(.*?)\n(.*)/s;
my $RE_YAML_MARKDOWN = qr/\s*(---\n.*?\.\.\.\n)?(.*)/sm;
my $RE_TAG           = qr/^[\p{Ll}\d]+(?: [\p{Ll}\d]+)*$/;

my $RE_TITLE         = qr/\[% \s* title    \s* %\]/x;
my $RE_URL           = qr/\[% \s* url      \s* %\]/x;
my $RE_HASHTAGS      = qr/\[% \s* hashtags \s* %\]/x;

output_tweets( get_config() );

sub get_config {

    my %arguments = (
        'template-filename' => undef,
        'blog-url'          => undef,
        'version'           => 0,
        'help'              => 0,
    );

    GetOptions(
        \%arguments,
        'template-filename=s',
        'blog-url=s',
        'version',
        'help',
    );

    show_usage_and_exit() if $arguments{ help };

    if ( $arguments{ version } ) {
        print "$VERSION\n";
        exit;
    }

    my $missing = 0;
    my %required = (
        'template-filename' =>
            'Use --template-filename to specify a template',
        'blog-url' =>
            'Use --blog-url to specify the URL of the blog itself',
    );
    for my $name ( sort keys %required ) {
        if ( !defined $arguments{ $name } ) {
            warn "$required{ $name }\n";
            $missing++;
        }
    }
    show_usage_and_exit( 2 ) if $missing;

    my $filename = shift @ARGV;
    if ( !defined $filename ) {
        warn "Specify a filename that contains the entries\n";
        show_usage_and_exit(1);
    }
    warn "Additional arguments have been skipped\n" if @ARGV;

    my %config = %arguments;
    $config{ filename } = $filename;
    $config{ template } = path( $config{ 'template-filename' } )
        ->slurp_utf8();

    return \%config;
}

sub output_tweets {

    my $config = shift;

    my $days = ( collect_days_and_pages(
        read_entries( $config->{ filename } )
    ) )[ 0 ];

    for my $day ( @$days ) {
        my %tags;
        my @articles;
        my $article_no = 1;
        for my $article ( @{ $day->{ articles } } ) {
            try {
                my ( $yaml, $md ) = $article =~ $RE_YAML_MARKDOWN;
                $yaml or die 'No mandatory YAML block found';

                my $meta = Load $yaml;
                ref $meta eq 'HASH' or die 'YAML block must be a mapping';

                exists $meta->{tags} or die 'No tags are specified';
                validate_tags( $meta->{ tags } );
                $tags{ $_ }++ for @{ $meta->{ tags } };
            }
            catch {
                my ( $error ) = $_ =~ /(.*) at /s;
                die "$error in article $article_no of $day->{ date }\n";
            };
            $article_no++;
        }

        my @hashtags;
        for my $tag ( keys %tags ) {
            my @parts = split / /, $tag;
            if ( @parts > 1 ) {
                push @hashtags, '#' . join( '', map { ucfirst } @parts );
            }
            else {
                push @hashtags, "#$tag";
            }
        }

        my ( $year, $month, $day_number ) = split_date( $day->{ date } );
        my $url = URI->new_abs(
            "archive/$year/$month/$day_number.html",
            $config->{ 'blog-url' }
        )->as_string();

        my $tweet = $config->{ template };
        for ( $tweet ) {
            s/ $RE_TITLE    /$day->{ title }/gx;
            s/ $RE_URL      /$url/gx;
            s/ $RE_HASHTAGS /@hashtags/gx;
        }
        print $tweet;
        print "%\n";
    }
}

sub validate_tags {

    my $tags = shift;

    ref $tags eq 'ARRAY' or die 'Tags must be specified as a list';

    my %seen;
    for my $tag ( @$tags ) {
        length $tag or die 'A tag must have a length';
        $tag =~ $RE_TAG or die "Invalid tag '$tag' found";
        ++$seen{ $tag } == 1 or die "Duplicate tag '$tag' found";
    }
    return;
}

sub split_date {

    return split /-/, shift;
}

sub strip {

    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub collect_days_and_pages {

    my $entries = shift;

    my @days;
    my @pages;
    my $state = 'unknown';
 ENTRY:
    for my $entry ( @$entries ) {
        if ($entry =~ $RE_DATE_TITLE ) {
            my $title = strip( $2 );
            $title ne '' or die "A day must have a title ($1)\n";
            push @days, {
                date     => $1,
                title    => $title,
                articles => [ $3 ],
            };
            $state = 'date-title';
            next ENTRY;
        }
        if ( $entry =~ $RE_AT_PAGE_TITLE ) {
            my $title = strip( $5 );
            $title ne '' or die "A page must have a title (\@$1)\n";
            push @pages, {
                name        => $1,
                label       => strip($2),
                date        => $3,
                'show-date' => $4 eq '!',
                title       => $title,
                articles    => [ $6 ],
            };
            $state = 'at-page-title';
            next ENTRY;
        }

        if ( $state eq 'date-title' ) {
            push @{ $days[ -1 ]{ articles } }, $entry;
            next ENTRY;
        }

        if ( $state eq 'at-page-title' ) {
            push @{ $pages[ -1]{ articles } }, $entry;
            next ENTRY;
        };

        die 'No date or page specified for first tumblelog entry';
    }

    @days  = sort { $b->{ date } cmp $a->{ date } } @days;
    @pages = sort { $b->{ date } cmp $a->{ date } } @pages;

    return ( \@days, \@pages );
}

sub read_entries {

    my $filename = shift;
    my $entries = [ grep { length $_ } split /^%\n/m,
                    path( $filename )->slurp_utf8() ];

    @$entries or die 'No entries found';

    return $entries;
}

sub show_usage_and_exit {

    my $exit_code = shift // 0;

    print { $exit_code ? *STDERR : *STDOUT } <<'END_USAGE';
NAME
        md2tweets - Parses a tumblelog Markdown file and outputs tweets to
                    the standard output.

SYNOPSIS
        md2tweets.pl --template-filename TEMPLATE --blog-url URL FILE
        tumblelog.pl --version
        tumblelog.pl --help
DESCRIPTION
        Obtains titles, dates, and tags from the given FILE and writes
        tweets to the standard output using the TEMPLATE in a format
        suitable for tweetfile.pl.

        The --version option shows the version number and exits.

        The --help option shows this information.
END_USAGE

    exit $exit_code;
}
