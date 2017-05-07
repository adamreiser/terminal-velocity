$VERSION = "0.01";

use strict;
use warnings;

package Galaxy;

sub new {

    my $class = shift;

    my $self = {};

    bless( $self, $class );

    $self->{meta}{fname} = shift;
    $self->{meta}{fname} .= "__Data";

    $self->{meta}{data_dir} = shift;

    #print "Data dir is $self->{'data_dir'}\n";
    $self->reSource("dësc");
    $self->reSource("spöb");
    $self->reSource("sÿst");
    $self->reSource("jünk");
    $self->reSource("öops");
    $self->reSource("mïsn");
    $self->reString("STR#");

    # Figure out the last commodity index number. There are 6 base commodities
    # starting at zero, so if any junks are defined, they are numbered 6 and up.
    if ( scalar keys %{ $self->{junk} } > 0 ) {
        my @junks = sort { $a <=> $b } keys %{ $self->{junk} };
        $self->{meta}{lastgood} = ( $junks[-1] - 128 + 6 );
    }

    return $self;

}

sub reSource {
    my $self = shift;

    my $type = shift;

    # Remove umlauts from type names.
    # Perl can handle hash keys with umlauts, but not as barewords.
    # So $evc{'dësc'} works, but $evc{desc} doesn't.

    my $sanitype = $type;

    $sanitype =~ s/ä/a/g;
    $sanitype =~ s/ë/e/g;
    $sanitype =~ s/ï/i/g;
    $sanitype =~ s/ö/o/g;
    $sanitype =~ s/ü/u/g;
    $sanitype =~ s/ÿ/y/g;

    # TODO: ensure that double quotes are handled.
    # Fortunately, the scenario data uses "smart quotes"
    my $fname = "$self->{meta}{data_dir}/$self->{meta}{fname}/$type";

    open(FILE, $fname) or die("Could not open $fname");

    # get the first line for the definitions
    my $line = <FILE>;

    my @fields;

    while ( $line =~ /"(?:([^"]+)")|(?:(\S+)\s|$)/g ) {

        push @fields, $1 if defined $1;
        push @fields, $2 if defined $2;

        # $1 should match things in quotes (which cannot have quotes in them)
        # $2 should match other things (which cannot have spaces in them)

        ## Debug
        ##
        ##if (defined $1) { print "\$1 Matched $1\n"; }
        ##if (defined $2) { print "\$2 Matched $2\n"; }
        ##if ((! defined $1) && (! defined $2)) { print "both blank!\n"; }

    }

    # Each next line is an ordered set of values for the line's type.

    my $i = 0;

    my %allspobs;

    while ( $line = <FILE> ) {

        next if $line eq "\n";

        my %spob;

        $i = 0;

        while ( $line =~ /"(?:([^"]+)")|(?:(\S+)\s|$)/g ) {

            $spob{ $fields[$i] } = $1 if defined $1;
            $spob{ $fields[$i] } = $2 if defined $2;
            $i++;
        }

        # Each resource must have a unique ID.
        $allspobs{ $spob{'ID'} } = \%spob;

    }
    close(FILE);

    # Note that since this is a nested hash, the memory allocated to
    # %allspobs continues to be used.
    # Even when we run reSource multiple times, overwriting the lexical
    # variable %allspobs, the previous %allspobs has the same memory address,
    # which allows the higher level hash to find it.

    $self->{$sanitype} = \%allspobs;
    return $self;

}

sub reString {
    my $self = shift;
    my $type = shift;
    my $fname = "$self->{meta}{data_dir}/$self->{meta}{fname}/$type";

    open(STR, $fname) or die("Could not open $fname");

    # Word pattern
    my $pw = q/\s*"([^"]*)"/;

    # Number pattern
    my $pn = q/\s*(\d+)/;

    # Strings pattern. "•" indicates end-of-record.
    #my $st = q/\s*(.*?)\s*"•"/;
    my $st = q/\s*(.*?)\s*"\xe2\x80\xa2"/;

    # temp string var
    my $strings = '';
    my $id = -1;

    while (<STR>) {
        my $text = $_;
        if ( $text =~ /$type$pn$pw$pw$pn$st/g ) {
            my $id = $1;
            $strings = $5;
            $self->{$type}{$id}{Type} = $type;
            $self->{$type}{$id}{Name} = $2;
            $self->{$type}{$id}{File} = $3;
            $self->{$type}{$id}{n}    = $4;

            my @tmp = ();

            while ($strings =~  /"(.*?)"/g) {
                push(@tmp, $1);
            }

            $self->{$type}{$id}{Strings} = \@tmp;

        }
    }

    close STR;
    return $self;
}

return 1;

