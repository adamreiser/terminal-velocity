$VERSION = "0.01";


# TODO: clean up reliance on package variables

package Market;

sub new {

    my $class = shift;
    my $self  = {};
    bless( $self, $class );
    return $self;
}

sub create {
    my $self = shift;
    $self->doAddCommo($_) for 0 .. 5;
    $self->doAddJunk();
    return $self;
}

sub erase {
    my $self = shift;
    delete $self->{$_} for keys %{$self};
    return $self;
}

# What happens if a junk is sold at more than one price on a
# given spob?

sub doAddJunk {
    my $self = shift;

    # regular commodities = 0-5
    my $comdex = 0;
    my $idx_junk_id;

    my $i;

    for $idx_junk_id ( sort keys %{ $main::ev->{junk} } ) {

        # idx_junk_id 128 is $comdex = 6
        $comdex = $idx_junk_id - 128 + 6;

        for $i ( 1 .. 8 ) {
            if ( $main::ev->{junk}{$idx_junk_id}{"BoughtAt$i"} ==
                $main::player{spob} )
            {
                $self->{$comdex}{name} = $main::ev->{junk}{$idx_junk_id}{Name};
                $self->{$comdex}{price} =
                  int $main::ev->{junk}{$idx_junk_id}{BasePrice} * 1.25;
                $self->{$comdex}{pricedesc} = "High";
            }

            if ( $main::ev->{junk}{$idx_junk_id}{"SoldAt$i"} ==
                $main::player{spob} )
            {
                $self->{$comdex}{name} = $main::ev->{junk}{$idx_junk_id}{Name};
                $self->{$comdex}{price} =
                  int $main::ev->{junk}{$idx_junk_id}{BasePrice} * .75;
                $self->{$comdex}{pricedesc} = "Low";
            }

            # only max one instance of being sold twice in a particular market
            last;

        }

    }
    return $self;

}

sub doAddCommo {

    # The market object being created
    my $self = shift;

    # commodity index value - 0 to 5
    my $comdex = shift;

    # Goods can theoretically be offered at all three prices on
    # a spob.

    # Base price
    my $bp = $main::ev->{'STR#'}{4004}{Strings}[$comdex];

    # Actual price for this market.

    # Note that events (e.g., rockslide on New Columbia) can
    # cause goods to be sold when they wouldn't otherwise be.

    my $ap = $bp;

    my $pricedesc = '';

    if ( &main::checkBit( 'spob', $main::player{spob}, $comdex, 4 ) ) {
        $ap        = int $bp * 1.25;
        $pricedesc = 'High';
    }

    if ( &main::checkBit( 'spob', $main::player{spob}, $comdex, 2 ) ) {
        $pricedesc = 'Medium';
    }

    if ( &main::checkBit( 'spob', $main::player{spob}, $comdex, 1 ) ) {
        $pricedesc = 'Low';
        $ap        = int $bp * .75;
    }

    # Check active events. If multiple active events affect a
    # commodity's price, only apply the last one.
    for ( keys %main::oops ) {

        # The event occurs here
        if ( $main::oops{$_}{spob} == $main::player{spob} ) {

            # The event affects the price of this commodity
            if ( $main::oops{$_}{commodity} == $comdex ) {
                $ap += $main::oops{$_}{pricedelta};

                # Some events can apparently cause price to drop below zero.
                # "Record fish harvest" (EV) for example, drops food by 300.
                # 'Fix' this by changing negative prices to 1/15 instead.
                # In the actual game, food on Levo drops from 120 to 5.

                # An event could also cause a commodity to simply be
                # sold at its base price when it otherwise wouldn't
                # be offered.

                if ( $ap < 0 ) { $ap = int( $bp / 15 ); }

                if ( $main::oops{$_}{pricedelta} < 0 ) {
                    $pricedesc = "Lower";
                }
                elsif ( $main::oops{$_}{pricedelta} > 0 ) {
                    $pricedesc = "Higher";
                }

                else {
                    $pricedesc = "Medium";
                }
            }

        }
    }

    # If it's sold here, we've assigned a price description by this point
    if ( $pricedesc ne '' ) {
        $self->{$comdex}{name}  = $main::ev->{'STR#'}{4000}{Strings}[$comdex];
        $self->{$comdex}{price} = $ap;
        $self->{$comdex}{pricedesc} = $pricedesc;
    }

    return $self;
}

return 1;
