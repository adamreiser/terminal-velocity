#!/usr/bin/perl

use strict;
use warnings;
use Text::Wrap;
use Curses;
use Storable qw(retrieve);
use Market;
use Builder;
use Safe;

my $debug = 0;

my %name_map = ('ev' => 'EVC', 'evo' => 'UTF8EVO', 'fh' => 'FH', 'evn' => 'Nova', 'nova' => 'Nova');

my $scenarios = (join(", ", (sort keys %name_map)));

if (length(@ARGV < 1)) {
    print("Usage: $0 [SCENARIO] (available scenarios: $scenarios)\n");
    exit;
}

my $easy_name = $ARGV[0];
    unless (grep( /^$easy_name$/, keys %name_map)) {
        die("Must match one of $scenarios\n");
    }

my $db_path = "universe/$name_map{$easy_name}.db";

if (! -e $db_path) {
    Builder->new($name_map{$easy_name}); 
}

our $ev = retrieve($db_path);

# nova control bits
our %bits;

# evalNCB
my $compartment = new Safe;
$compartment->share_from('main', [ '%bits' ]);

# Text::Wrap
my ( $it, $st ) = ( "\t", '' );

# Cursor position
my ( $y, $x );

my $win = new Curses;

if ( has_colors() ) {
    start_color();
    init_pair( 1, COLOR_GREEN,  COLOR_BLACK );
    init_pair( 2, COLOR_CYAN,   COLOR_BLACK );
    init_pair( 3, COLOR_YELLOW, COLOR_BLACK );
    init_pair( 4, COLOR_RED,    COLOR_BLACK );
    init_pair( 5, COLOR_WHITE,  COLOR_BLACK );
    $win->attron( COLOR_PAIR(1) );
}

our %player;          # primary hash containing player data
my $input    = '';    # this is a single character of input
my $main_msg = '';    # for navigation and similar messages
my $sys_msg  = '';    # for debug messages and the '?' page
my $holovid  = '';    # displays extra string while in bars
our %oops;            # hash of any currently active events
my $clock = 0;        # records the length of the adventure

my $generic_error = "Enter '?' for help.";

# A 'market' is a set of prices for the commodities bought
# and sold at a given time and place. All spobs have fixed
# price levels for each commodity, but may change based on
# random or triggered events. Markets are created whenever
# the player visits a commodity exchange, and deleted when
# the player leaves the spaceport

my $market = Market->new();

# "space objects" menu = 0
# "hyperlinks"    menu = 1

my $menu = 1;

# $player{area} codes

# 0  = in space
# 1  = main spaceport
# 2  = spaceport bar
# 21 = at holovid (in bar)
# 3  = marketplace

$player{area} = 0;       # Start in space
$player{syst} = 128;     # ID number of starting syst
$player{spob} = -1;      # Not on a spob
$player{cash} = 10000;

$main_msg = "Welcome to Terminal Velocity!";

# Navigation menu indicies; these are not IDs.

# Selected commodity (0 to 5, 6+ for junk or -1 for none)
my $idx_i = -1;

# Selected neighbor (0 to 15 or -1)
my $idx_j = selectFirstLink();

# Selected spob (0 to 15 or -1)
my $idx_k = selectFirstSpob();

# Set $sysnav and $spobnav to the first visible neighbor and
# first spob, respectively. If no visible neighbors exist or
# no spobs are in the current system, then set to default -1

my ( $sysnav, $spobnav ) = setNavigation();

# Display output for the current turn
doNav();

# Main control loop
# ERR check in case input stream ends
while ( $input ne 'q' and $input ne Curses::ERR) {

    # Select the next menu item
    if ( $input eq '\\' or $input eq ' ' ) {

        $sys_msg = '';

        if ( $player{area} == 0 ) {

            # Select next neighbor, if any exist and are visible
            if ( $menu == 1 ) {

                # Get a list of visible neighbors
                my @visibleneighbors;
                for ( getNeighbors( $player{syst}, 0 ) ) {
                    push( @visibleneighbors, $_ )
                      if evalNCB( $ev->{syst}{$_}{Visibility} );
                }

                # If at least one neighbor exists and is visible
                if ( scalar @visibleneighbors != 0 ) {
                    do {
                        # Get the next neighbor number
                        $idx_j++;
                        $idx_j %= 16;

                  # While selected system is invisible, get next neighbor number
                        while (
                            !evalNCB(
                                $ev->{syst}
                                  { $ev->{syst}{ $player{syst} }{"con$idx_j"} }
                                  {Visibility}
                            )
                          )
                        {
                            $idx_j++;
                            $idx_j %= 16;
                        }
                      } while (
                        $ev->{syst}{ $player{syst} }{"con$idx_j"} == -1 );
                }
            }

            # Select next spob if any exist
            if ( $menu == 0 and scalar getSpobs( $player{syst}, 0 ) != 0 ) {
                do { $idx_k++; $idx_k %= 16; }
                  while $ev->{syst}{ $player{syst} }{"nav$idx_k"} < 0;
            }

 # Now that we've set either a new idx_j or idx_k, apply it to $sysnav, $spobnav
            ( $sysnav, $spobnav ) = setNavigation();
        }

        # If we're in a market, select the next good
        elsif ( $player{area} == 3 ) {

            # Don't let player select what isn't sold here

            # Increment selection by 1, then keep incrementing until we
            # reach a good that's sold here or we run out of goods.

            # TODO: commodity exchange exists but has nothing for sale?

            if ( scalar keys %{$market} != 0 ) {
                do {
                    $idx_i++;
                    $idx_i %= scalar( keys %{$market} );

                } while ( !defined( $market->{$idx_i}{price} ) );
            }
        }

        doNav();
        next;
    }

    # Set navigation to the numbered spob. This method can't select
    # spobs numbered past 9. (We start at 1 instead of zero since
    # that's what the original game does.)

    if ( $input =~ /([1-9])/ ) {

        # Resizing the window can send large numbers to getch
        if ( $input > 9 ) { }

        # Player in flight?
        elsif ( $player{area} == 0 ) {

            # Spob array starts at zero
            $input--;

            # TODO: how to handle wormholes?
            if ( $ev->{syst}{ $player{syst} }{"nav$input"} != -1 ) {
                $idx_k   = $input;
                $spobnav = $ev->{syst}{ $player{syst} }{"nav$idx_k"};
            }
            else {
                $sys_msg = "Stellar not found.";
            }
        }

        # Not in flight
        else {
            $sys_msg = $generic_error;
        }

        doNav();
        next;
    }

    # Hyperspace jump to $sysnav
    if ( $input eq 'j' ) {

        # Can't jump while landed
        if ( $player{area} != 0 ) {
            $sys_msg = "Unable to hyperjump; ";
            $sys_msg .= "leave $ev->{spob}{$player{spob}}{Name} first.";
            doNav();
            next;
        }

        # Shouldn't be possible to have no system selected unless there
        # are no connecting systems, e.g., S7evyn.
        elsif ( $sysnav == -1 ) {
            $sys_msg .= "No system selected.";
            doNav();
            next;
        }

        # Go to warp!
        $sys_msg      = '';
        $player{spob} = -1;
        $player{syst} = $sysnav;

        # Reset spob and syst selections
        $idx_j = selectFirstLink();
        $idx_k = selectFirstSpob();

        ( $sysnav, $spobnav ) = setNavigation();

        # Set warp-in message
        if ( $ev->{syst}{ $player{syst} }{Message} > 0 ) {
            $main_msg = $ev->{'STR#'}{1000}{Strings}
              [ $ev->{syst}{ $player{syst} }{Message} - 1 ];
        }

        else {
            $main_msg =
              "Warping into the $ev->{syst}{$player{syst}}{Name} system...";
        }

        doDay();
        doNav();
        next;
    }

    # Land on $spobnav
    # TODO: Check legal status, including 32767 (require rank)

    if ( $input eq 'l' ) {

        $main_msg = '';
        $sys_msg  = '';

        # Catch simple reasons why we might not be able to land
        if ( $player{area} != 0 ) {
            $sys_msg = "Leave $ev->{spob}{$player{spob}}{Name} first.";
        }

        # If we are in space, but there are no spobs in this system
        elsif ( scalar( getSpobs( $player{syst}, 0 ) == 0 ) ) {
            $sys_msg = "No stellar objects present.";
        }

        # If we are in space, and there are spobs,
        # then one of them must be selected ($spobnav)
        # Possible to land/dock?
        elsif ( checkBit( 'spob', $spobnav, 7, 1 ) ) {

          # TODO: when we implement legal status, check if we're allowed to land

            # Is the spob a hypergate?
            if ( checkBit( 'spob', $spobnav, 0, 1, 2 ) ) {

                # TODO: let the player use hypergates
                $sys_msg = "Hypergate usage denied.";
            }

            # Not a hypergate
            else {
                $player{spob} = $spobnav;    # Put player on targeted spob
                $player{area} = 1;           # Put player in main spaceport
                $spobnav      = -1;          # Reset targeting
                $sysnav       = -1;
                $idx_j = -1;    # We might get teleported to a place with no
                $idx_k = -1;    # spobs or links so reset these indicies
            }
        }

# Can't land/dock. Should this message be hardcoded, or read from the string file?
        else {
            $sys_msg = "Your ship is unable to ";

            # Is it a hypergate? (shouldn't matter whether planet or station).
            if ( checkBit( 'spob', $spobnav, 0, 1, 2 ) ) {
                $sys_msg .= "enter this hypergate - it is offline.";
            }

            # Not a hypergate, so check if it's a planet or station.
            else {
                if ( checkBit( 'spob', $spobnav, 6, 1 ) ) {
                    $sys_msg .=
"dock at $ev->{spob}{$spobnav}{Name}. The station’s hull integrity is too unstable.";
                }
                else {
                    $sys_msg .=
"land on $ev->{spob}{$spobnav}{Name}. The planet's environment is too hostile.";
                }
            }
        }

        doNav();
        next;

    }

    # Spaceport bar (while in spaceport)
    # Buy goods     (while in market)

    if ( $input eq 'b' ) {

        $sys_msg  = '';
        $main_msg = '';

        # TODO: implement cargo hold size
        if ( $player{area} == 3 ) {

            # Can we afford 10 tons?
            if ( $player{cash} >= $market->{$idx_i}{price} ) {
                $player{cargo}{$idx_i} += 10;
                $player{cash} -= $market->{$idx_i}{price};
            }

            # If we can't afford 10 tons, buy as much as we can.
            else {
                while ( $player{cash} >= $market->{$idx_i}{price} / 10 ) {
                    $player{cargo}{$idx_i}++;
                    $player{cash} -= $market->{$idx_i}{price} / 10;
                }
            }
            doNav();
            next;
        }

        # Are we in the main spaceport? Then 'b' means to go to the bar.
        elsif ( $player{area} == 1 ) {

            # Is there a bar here?
            if ( checkBit( 'spob', $player{spob}, 6, 4 ) ) {
                $player{area} = 2;
            }
            else {
                $sys_msg = "There appear to be no bars in the vicinity.";
            }
        }

        # Not in a market or the main spaceport.
        else {
            $sys_msg .= $generic_error;
        }

        doNav();
        next;

    }

    # Commodity exchange
    if ( $input eq 'c' ) {

        $sys_msg = '';

        # 'c' only has meaning in the main spaceport
        if ( $player{area} != 1 ) {
            $sys_msg .= $generic_error;
        }

        # does the spob have a market?
        else {
            if ( checkBit( 'spob', $player{spob}, 7, 2 ) ) {
                $player{area} = 3;
                $market->create();
                $idx_i = 0;

                # Select first available commodity;
                # assumes market buys/sells at least one commodity
                while ( !defined( $market->{$idx_i}{price} ) ) {
                    $idx_i++;
                    $idx_i %= scalar( keys %{$market} );
                }
            }

            # If the spob does not have a market
            else {
                $sys_msg = "There appear to be no markets in the vicinity.";
            }

        }
        doNav();
        next;
    }

    # Leave current area and return to space
    if ( $input eq 'h' ) {

        # Are we on a planet?
        if ( $player{area} > 0 ) {
            $market->erase();

            $idx_i    = -1;
            $idx_j    = selectFirstLink();
            $idx_k    = selectFirstSpob();
            $sys_msg  = '';
            $main_msg = "Taking off from $ev->{spob}{$player{spob}}{Name}...";
            $player{spob} = -1;
            $player{area} = 0;

            ( $sysnav, $spobnav ) = setNavigation();

            doDay();
        }
        else {
            $sys_msg = $generic_error;
        }
        doNav();
        next;
    }

    # Sell goods

    if ( $input eq 's' ) {

        # are we in a market?
        if ( $player{area} != 3 ) {
            $sys_msg = $generic_error;
        }

        else {

            # Do we have any of the selected commodities?
            # We don't have to check if the market buys these
            # commodities, since the player can't select them if
            # it doesn't.
            if ( defined $player{cargo}{$idx_i} ) {

                # Do we have at least 10 tons?
                if ( $player{cargo}{$idx_i} >= 10 ) {
                    $player{cargo}{$idx_i} -= 10;
                    $player{cash} += $market->{$idx_i}{price};
                }

                # if we don't, sell whatever we have.
                else {
                    $player{cash} +=
                      $market->{$idx_i}{price} * $player{cargo}{$idx_i} / 10;
                    $player{cargo}{$idx_i} = 0;
                }

            }

            # Don't display error message on trying to sell cargo we don't have,
            # but here's how we'd do it.

            # else {
            #   $sys_msg = "You have no $ev->{'STR#'}{4001}{Strings}[$idx_i].";
            # }

            # Don't store zero values of carried cargo
            if ( defined $player{cargo}{$idx_i} and $player{cargo}{$idx_i} < 1 )
            {
                delete $player{cargo}{$idx_i};
            }

        }
        doNav();
        next;

    }

    # Inventory: wordy cargo display
    if ( $input eq 'i' ) {

        $sys_msg = '';

        # Are we carrying any cargo?
        if ( scalar keys %{ $player{cargo} } > 0 ) {

            my @cargo;

            # 0-5 are the regular commodities, anything higher is a junk ID
            for ( sort { $a <=> $b } keys %{ $player{cargo} } ) {

                # Strings for regular commodities
                if ( $_ < 6 ) {
                    push( @cargo,
"$player{cargo}{$_} tons of $ev->{'STR#'}{4001}{Strings}[$_]"
                    );
                }

                # Strings for junks
                else {
                    push( @cargo,
"$player{cargo}{$_} tons of $ev->{junk}{$_-6+128}{LCName}"
                    );
                }
            }

            # Grammar
            if ( scalar @cargo > 1 ) {
                $cargo[-1] = "and $cargo[-1].";
            }
            else {
                $cargo[-1] .= ".";
            }

            # Serial comma
            if ( scalar @cargo > 2 ) {
                $main_msg = join( ", ", @cargo );
            }
            else {
                $main_msg = join( " ", @cargo );
            }
        }

        else {
            $main_msg = "You are carrying no cargo.";
        }

        if ($debug) {
            $main_msg .=
                "\n\tidx_j  = $idx_j\n\t"
              . "idx_k  = $idx_k\n\t"
              . "idx_i  = $idx_i";
            $main_msg .= "\n\tsysnav = $sysnav";
            $main_msg .= "; Vis = " . $ev->{syst}{$sysnav}{Visibility}
              if $sysnav != -1;
            $main_msg .= "\n\tmenu   = $menu";
        }

        doNav();
        next;

    }

    # Watch holovid
    if ( $input eq 'v' ) {

        # Entering 'v' while already in the holovid loads new messages.
        if ( $player{area} == 2 or $player{area} == 21 ) {
            $player{area} = 21;

            $main_msg = '';
            $sys_msg  = '';

            # First story is a commercial
            $holovid = "\n\t" . getString(8100);

            # 1/3 chance that the second story is event news, if applicable
            if ( int( rand 3 ) < 1 and ( scalar keys %oops ) > 0 ) {

                # ID number of a random active event
                my $evnt = ( keys %oops )[ int( rand( scalar keys %oops ) ) ];

                # Is the random event not mission news?
                if ( $oops{$evnt}{spob} != -2 ) {
                    $holovid .= "\n\n\t";
                    $holovid .= "$oops{$evnt}{name} has ";

                    # If price delta is zero, say the price was raised
                    $holovid .=
                      $oops{$evnt}{pricedelta} < 0 ? "lowered" : "raised";
                    $holovid .= " the price of ";
                    $holovid .=
                      $ev->{'STR#'}{4001}{Strings}[ $oops{$evnt}{commodity} ];
                    $holovid .= " on $ev->{spob}{$oops{$evnt}{spob}}{Name}.\n";
                }

                # If event is not commodity news, display its special string.
                # If it doesn't exist, second story will be blank.
                elsif ( $ev->{'STR#'}{8102}[ $evnt - 128 ] ) {
                    $holovid .= "\n\n\t" . $ev->{'STR#'}{8102}[ $evnt - 128 ];
                }
            }

            # 2/3 chance that second story is random, non-event news
            else {
                $holovid .= "\n\n\t" . getString(8101) . "\n";
            }
        }

        # If player is not in a spaceport bar or already in the holovid
        else {
            $sys_msg = $generic_error;
        }

        doNav();
        next;

    }

    # Tab shifts focus to the next menu
    if ( $input eq "\t" ) {

        # Make sure menu screen is up
        # TODO: Make tab select menu while on a spob?
        if ( $player{area} == 0 ) {
            $menu++;
            $menu %= 2;
        }
        else {
            $sys_msg = $generic_error;
        }
        doNav();
        next;
    }

    # Debug commands
    if ( $input eq 'x' ) {
        if ($debug) {
            $sys_msg = '';
            for ( sort { $a <=> $b } keys %oops ) {
                $sys_msg .= "$oops{$_}{name} ";
                $sys_msg .= "on $ev->{spob}{$oops{$_}{spob}}{Name} ";
                $sys_msg .= "($oops{$_}{timeleft}). ";
            }
        }
        else {
            $sys_msg = $generic_error;
        }

        doNav();
        next;

    }

    # Display help screen
    if ( $input eq '?' ) {

        $sys_msg = "Welcome to Terminal Velocity!\n\n";
        $sys_msg .= <<END;
\tCommands are entered as single keystrokes and depend on your current location. Some work while in flight, other while docked.

\t Spaceflight
\t\t (space or '\\') Select next choice from current menu
\t\t (tab) Switch active menu
\t\t j Hyperjump to selected system
\t\t (1-9) Alternative way to select a space object

\t Landed or docked
\t\t (enter) Leave current area
\t\t l Land
\t\t b Spaceport bar
\t\t c Commodity exchange
\t\t b Buy commodity (commodity exchange)
\t\t s Sell commodity (commodity exchange)
\t\t v Visit holovid (bar)

\t Universal
\t\t i Display cargo
\t\t q Quit
\t\t ? This help message

\n\tPress any key to continue...
END

        $win->clear();
        $win->attron(A_BOLD);
        $win->addstr( wrap( $it, $st, $sys_msg ) );
        $win->attroff(A_BOLD);
        $win->refresh();

        $input = "\n";

        $win->getmaxyx( $y, $x );
        $win->getch( $y - 2, 8 );

        next;
    }

    if ( $input eq "\n" ) {

        # Clear messages first
        $main_msg = '';
        $sys_msg  = '';

        # Reset goods selection
        $idx_i = -1;

        # Are we not in space?
        if ( $player{area} != 0 ) {

            # Are we in the main spaceport?
            if ( $player{area} == 1 ) {
                $main_msg =
                  "Taking off from $ev->{spob}{$player{spob}}{Name}...";
                $player{spob} = -1;
                $player{area} = 0;
                $idx_j        = selectFirstLink();
                $idx_k        = selectFirstSpob();

                ( $sysnav, $spobnav ) = setNavigation();

                doDay();

            }

            #...and in a bar, comm exchange, etc.
            if ( $player{area} > 1 and $player{area} < 10 ) {

                #...then go to main spaceport.
                $player{area} = 1;
                $market->erase();
            }

            #...but if we're in a subarea, like the holovid (21)
            if ( $player{area} == 21 ) {

                # ...then go back to the bar!
                $player{area} = 2;
            }

        }

        # If we're not on a planet, then clear all messages
        else {
            $main_msg = '';
            $sys_msg  = '';
        }

        doNav();
        next;
    }

    # ###END ACCEPTED COMMAND SECTION ########
    # if we reach this region of the loop, it
    # means either the player has entered
    # an invalid command, or we've forgotten
    # a 'next;' in one of the above
    # conditions.
    ##########################################

    $sys_msg = $generic_error;

    doNav();

}

# Given a syst ID and mode, returns array of IDs or names
# Usage: getSpobs(128, 0|1)

sub getSpobs {
    my $local = shift;
    my $mode  = shift;
    my $spob  = '';
    my $S_ID  = -1;
    my @spobs;

    #MAXSPOBS = 15

    if ( $mode == 0 ) {
        for ( 0 .. 15 ) {
            $S_ID = $ev->{'syst'}{$local}{"nav$_"};
            next if $S_ID eq '-1';
            push( @spobs, $S_ID ) if defined $S_ID;
        }
    }

    if ( $mode != 0 ) {
        for ( 0 .. 15 ) {
            $S_ID = $ev->{'syst'}{$local}{"nav$_"};
            next if $S_ID == -1;
            $spob = $ev->{'spob'}{$S_ID}{Name};
            push( @spobs, $spob ) if defined $spob;
        }
    }

    return @spobs;
}

# Given a syst ID and mode, returns array of IDs or names
# Usage: getNeighbors(128, 0|1);
sub getNeighbors {

    my $local = shift;
    my $mode  = shift;
    my $S_ID  = -1;

    my $neighbor = '';    # current neighbor

    my @neighbors;        # array to return

    #MAXSYSTS = 15

    if ( $mode == 0 ) {
        for ( 0 .. 15 ) {
            $S_ID = $ev->{'syst'}{$local}{"con$_"};
            next if $S_ID eq '-1';
            push( @neighbors, $S_ID );
        }

    }

    # print mode
    if ( $mode != 0 ) {
        for ( 0 .. 15 ) {
            $S_ID = $ev->{'syst'}{$local}{"con$_"};
            next if $S_ID eq '-1';
            $neighbor = $ev->{'syst'}{$S_ID}{'Name'};
            push( @neighbors, $neighbor );
        }
    }

    return @neighbors;
}

# Check to see if a flag is set. Returns true if it is.
# ($whichflags field is optional)

# checkBit( $type, $id, $pos, $value, $whichflags)

# Example:  if (checkBit('spob', 128, 7, 1)
# Checks to see if 0x00000001 is set on spob 128 (Flags)

# Example:  if (checkBit('spob', 1404, 0, 1, 2)
# Checks to see if 0x1000 is set on spob 1404 (Flags2)

sub checkBit {

    my $type      = shift;            # spob, syst, etc.
    my $id        = shift;            # 128 and up
    my $pos       = shift;            # flag position, i.e., 0x[0,1,2,3,4,5,6,7]
    my $value     = shift;            # value to test (1 to F)
    my $whichflag = ( shift or '' );

    my $result;
    my $testbit;

    $ev->{$type}{$id}{"Flags$whichflag"} =~ /0x.{$pos}(.)/;
    $testbit = hex $1;
    $result  = ( $testbit ^ $value );
    return $result < $testbit ? 1 : 0;
}

# Gets a random string from the given ID
sub getString {
    my $id = shift;
    my $nb = int rand( $#{ $ev->{'STR#'}{$id}{Strings} } );
    return $ev->{'STR#'}{$id}{Strings}[$nb];
}

# Main window drawing function
sub doNav {

    $win->clear();

    # Status line at the very top, no matter where we are
    $win->attron(A_BOLD);
    $win->addstr("Current system: $ev->{syst}{$player{syst}}{Name}");

    # Are we on a planet?
    if ( $player{area} != 0 ) {
        $win->addstr(" (on $ev->{spob}{$player{spob}}{Name})\n\n");
        $win->attroff(A_BOLD);

        if ( defined $ev->{desc}{ $player{spob} }{Description} ) {
            $win->addstr(
                wrap( $it, $st, "$ev->{desc}{$player{spob}}{Description}\n\n" )
            );
        }
        else { $win->addstr("\tThis place is non-descript.\n\n"); }
    }

    # TODO: make this menu selectable
    if ( $player{area} == 1 ) {

        $win->addstr("\n\n");

        # Has bar?
        if ( checkBit( 'spob', $player{spob}, 6, 4 ) ) {
            $win->addstr("\t[Spaceport bar]\n");
        }
        if ( checkBit( 'spob', $player{spob}, 7, 2 ) ) {
            $win->addstr("\t[Commodity exchange]\n");
        }
        $win->addstr("\t[Leave]\n");
    }

    # Not on a planet, add a blank line
    else { $win->addch("\n"); }

    $win->attroff(A_BOLD);

    # If we're in space, show the list of local spobs and hyperjumps
    if ( $player{area} == 0 ) {
        $win->attron(A_BOLD);

        # Get ships to line up with spobs without being part of same object.
        # See curses examples.

        # If the "local spobs" menu (0) is selected, make it stand out
        $win->attron( COLOR_PAIR(5) ) if $menu == 0;

        $win->addstr("\nSpace objects:\n\n");
        $win->attron( COLOR_PAIR(1) ) if $menu == 0;

        $win->attroff(A_BOLD);

        for ( getSpobs( $player{syst}, 0 ) ) {

            # If the current spob is selected, make it stand out
            $win->attron( COLOR_PAIR(3) ) if $_ == $spobnav;
            $win->attron(A_BOLD) if $_ == $spobnav;
            $win->addstr("\t$ev->{spob}{$_}{Name}\n");
            $win->attroff(A_BOLD);
            $win->attron( COLOR_PAIR(1) );

        }

        # Minimum height of spob display
        $win->addstr( "\n" x ( 5 - scalar getSpobs( $player{syst}, 0 ) ) );

        $win->attron(A_BOLD);

        # If the "navigation" menu (1) is selected, make it stand out
        $win->attron( COLOR_PAIR(5) ) if $menu == 1;
        $win->addstr("Hyperspace routes:\n\n");
        $win->attron( COLOR_PAIR(1) ) if $menu == 1;
        $win->attroff(A_BOLD);

        for ( getNeighbors( $player{syst}, 0 ) ) {

            next if !evalNCB( $ev->{syst}{$_}{Visibility} );

            $win->attron(A_BOLD) if $_ == $sysnav;
            $win->attron( COLOR_PAIR(3) ) if $_ == $sysnav;
            $win->addstr("\t$ev->{syst}{$_}{Name}\n");
            $win->attroff(A_BOLD);
            $win->attron( COLOR_PAIR(1) );
        }

        # Minimum height of syst display
        $win->addstr( "\n" x ( 5 - scalar getNeighbors( $player{syst}, 0 ) ) );
    }

    # if we're on a planet and in the bar (including in holovid)...
    if ( $player{area} == 2 or $player{area} == 21 ) {
        if ( defined $ev->{'desc'}{ $player{spob} - 128 + 10000 }{'Description'} )
        {
            $win->addstr( wrap($it, $st, "\n\n\t$ev->{desc}{$player{spob}-128+10000}{Description}\n\n") );
        }
        else
        {
            $win->addstr("\n\n\tThis is a non-descript bar.\n\n");
        }

    }

    # if we're in the holovid...
    if ($player{area} == 21) {
        $win->attron( COLOR_PAIR(2) );
        $win->addstr( wrap( $it, $st, $holovid ) );
        $win->attron( COLOR_PAIR(1) );
    }

    # Commodity exchange
    if ( $player{area} == 3 ) {
        $win->addstr(
            "\n\n\tWelcome to the commodity exchange! ($player{cash})\n\n");

        # For each type of cargo
        for ( 0 .. $ev->{meta}{lastgood} ) {

            # if it's not sold here...
            if ( !defined $market->{$_}{price} ) {

                # ...then print a blank line... (only for base goods)
                if ( $_ < 6 ) {
                    $win->addstr("\n");
                }

                # ...and check the next cargo type.
                next;
            }

            # If it is sold here...

            # make player selection stand out
            $win->attron(A_BOLD) if $idx_i == $_;
            $win->attron( COLOR_PAIR(3) ) if $idx_i == $_ and has_colors();
            $win->addstr("\t$market->{$_}{name}");

            # Buffer between cargo name and amount owned by player

            # TODO: check the longest cargo name (junk) and make
            # the buffer adjust to that size.
            $win->addstr( " " x ( 25 - length $market->{$_}{name} ) );

            # Check if player owns any
            if ( defined $player{cargo}{$_} ) {
                $win->addstr("$player{cargo}{$_}");

                # Buffer between amount owned and price description.
                $win->addstr( " " x ( 16 - length $player{cargo}{$_} ) );
            }
            else {
                $win->addstr( " " x 16 );
            }

            # Price description: low(er), medium, high(er).
            $win->addstr( $market->{$_}{pricedesc} );

            # Buffer
            $win->addstr( " " x ( 12 - length $market->{$_}{pricedesc} ) );

            # Numerical price
            $win->addstr("$market->{$_}{price}\n");

            # End of line
            $win->attroff(A_BOLD);
            $win->attron( COLOR_PAIR(1) ) if has_colors();
        }

        # Display oops messages, if any
        for ( keys %oops ) {
            if ( $oops{$_}{spob} == $player{spob} ) {
                my $msg = "$oops{$_}{name} has ";

                $msg .= $oops{$_}{pricedelta} < 0 ? "lowered" : "raised";
                $msg .=
" the price of $ev->{'STR#'}{4001}{Strings}[$oops{$_}{commodity}].";
                $win->addstr( wrap( $it, $st, "\n\t$msg" ) );
            }
        }
    }

    # $it has no effect since it comes before a newline.

    if ($main_msg) {
        $win->addstr( wrap( $it, $st, "\n\t$main_msg\n\n" ) );
    }

    $win->getmaxyx( $y, $x );

    $win->attron(A_BOLD);
    $win->attron( COLOR_PAIR(4) ) if has_colors();
    $win->addstr( wrap( '', '', "\n\t$sys_msg" ) );
    $win->attroff(A_BOLD);
    $win->attron( COLOR_PAIR(1) ) if has_colors();

    $win->refresh();

    $win->getmaxyx( $y, $x );

    $input = $win->getch( $y - 1, $x - 1 );
}

# Returns values to be assigned to sysnav and spobnav
# based on current system and idx_j, idx_k
sub setNavigation {

    my $syst = -1;
    my $spob = -1;

    if ( $idx_j != -1 ) {
        $syst = $ev->{syst}{ $player{syst} }{"con$idx_j"};
    }

    if ( $idx_k != -1 ) {
        $spob = $ev->{syst}{ $player{syst} }{"nav$idx_k"};
    }

    return ( $syst, $spob );
}

# Returns the 'neighbor index' of the first visible system (0 to 15).
# If there are no visible neighbors, returns -1.
sub selectFirstLink {

    my $j_try = 0;     # trial connection number
    my $j_ret = -1;    # final connection number
    my $try   = -1;    # ID of trial connection

    for $j_try ( 0 .. 15 ) {
        $try = $ev->{syst}{ $player{syst} }{"con$j_try"};

        # Is there a system at this index?
        if ( $try != -1 ) {
            if ( evalNCB( $ev->{syst}{$try}{Visibility} ) ) {
                $j_ret = $j_try;
                last;
            }
        }
    }
    return $j_ret;
}

# Select first spob (usually zero, or -1 if no spobs present)
sub selectFirstSpob {
    my $k_try = 0;     # trial nav number
    my $k_ret = -1;    # final nav number
    my $try   = -1;    # ID of trial spob

    for $k_try ( 0 .. 15 ) {
        $try = $ev->{syst}{ $player{syst} }{"nav$k_try"};

        # Is there a spob at this index?
        if ( $try != -1 ) {
            $k_ret = $k_try;
            last;
        }
    }
    return $k_ret;
}

# Dangerous little hack to evaluate nova control bits
sub evalNCB {

    # Some fields, like Visibility, are sometimes left blank
    my $expr = ( shift or 1 );

    # Evaluate to true if nothing to test.
    $expr = 1 if $expr eq '""';

    #$sys_msg = "Evaluating: $expr\n";
    $expr =~ s/\|/||/g;
    $expr =~ s/\&/&&/g;
    $expr =~ s/b(\d{1,4})/\$bits{b$1}/g;

    #$sys_msg .= "\tTranslated: $expr\n";

    return $compartment->reval($expr) ? 1 : 0;
}

sub doDay {

    # TODO: big ships take more than a day to jump
    my $timedelta = 1;
    $clock += $timedelta;

    my $tmp;

    # Some cargo multiplies like tribbles
    # TODO: check if this exceeds capacity of ship and determine growth rate
    for ( keys %{ $player{cargo} } ) {
        if ( $_ > 5 ) {
            $tmp = $ev->{junk}{ $_ + 128 }{Flags};
            $player{cargo}{$_} += int rand( hex($tmp) + 1 );
        }
    }

    # For each possible event in the galaxy
    for ( keys %{ $ev->{oops} } ) {

        # Check if it's already active
        if ( defined $oops{$_} ) {

            $oops{$_}{timeleft} -= $timedelta;

            # TODO: check if ActivateOn field is set. If it is, make sure
            # that the event is automatically triggered once and only once.
            if ( $oops{$_}{timeleft} < 0 ) {
                if ($debug) {
                    $sys_msg .= ( $oops{$_}{name} . " has ended.\n" );
                }
                delete $oops{$_};
            }
        }

       # If it wasn't already active or just deactivated, and isn't activated by
       # a control bit
        else {
            if ( ( int( rand 100 ) + 1 ) <= $ev->{oops}{$_}{Freq}
                and $ev->{oops}{$_}{ActivateOn} eq '""' )
            {

                $oops{$_}{name}       = $ev->{oops}{$_}{Name};
                $oops{$_}{timeleft}   = $ev->{oops}{$_}{Duration};
                $oops{$_}{pricedelta} = $ev->{oops}{$_}{PriceDelta};
                $oops{$_}{commodity}  = $ev->{oops}{$_}{Commodity};

                # Most events only affect specific spobs
                if ( $ev->{oops}{$_}{Stellar} > 127 ) {
                    $oops{$_}{spob} = $ev->{oops}{$_}{Stellar};
                }

                # Some events can strike anywhere
                elsif ( $ev->{oops}{$_}{Stellar} == -1 ) {
                    my $rand = int( rand( scalar keys %{ $ev->{spob} } ) );
                    my $id   = ( keys %{ $ev->{spob} } )[$rand];
                    $oops{$_}{spob} = $id;
                }

                # Some events don't affect any spob (mission news)
                # This is used as a test in the holovid message.
                elsif ( $ev->{oops}{$_}{Stellar} == -2 ) {
                    $oops{$_}{spob} = -2;
                }

                if ($debug) {
                    $sys_msg .=
                      ("$oops{$_}{name} ($ev->{spob}{$oops{$_}{spob}}{Name}). ");
                }
            }
        }
    }
}

endwin();
