package CGI::QuickData ; # Documented at the __END__.

# $Id: QuickData.pm,v 1.7 1999/11/04 22:21:01 root Exp root $

# TODO Make provision for generated (auto) values by adding options and
#      supporting code: 
#       -GENERATE_VALUE => \&callback, # e.g. for keyfields
#       -ALLOW_UPDATE   => 1, # e.g. false for generated keyfields
#       -ALLOW_INSERT   => 1, # e.g. false for generated keyfields
# TODO Test with mySQL and Postgresql
# TODO French & German message and label translations.
# TODO Don't quote the keyfield if its -DB_QUOTE is false.
#
# TODO Document!
#
# TODO lookups (drop down lists) for key X val tables (equiv Oracle LOVs)
# TODO drilldown support Table=tablename&Keyfield=fieldname&Orderby=fieldname&ID=value

require 5.004 ;

use strict ;

use CGI qw( :standard :html3 ) ;
use CGI::QuickForm qw( show_form colour ) ;
#use CGI::Carp ;
use DBI ;
use HTML::Entities ;
use URI::Escape ;

use vars qw( $VERSION @ISA @EXPORT $DB_HANDLE ) ;
$VERSION   = '0.02' ;

use Exporter() ;

@ISA       = qw( Exporter ) ;

@EXPORT    = qw( show_data $DB_HANDLE ) ;


my $ACTION = '.qfdb' ;
my( $ADD, $DELETE, $EDIT, $FIND, $LIST, $ORDERBY, $ORIGINALID, $REMOVE, 
    $SEARCH, $UPDATE, $WHERE ) = 
    qw( Add Delete Edit Find List OrderBy OriginalID Remove Search Update Where ) ;
my( $COMPARISON, $CONNECTOR, $VALUE ) = qw( comparison connector value ) ;
my $URL    = url() ;

my( $Action, $ID ) ;
my %Record ;


sub show_data {
    %Record = (
        -SHOW_SQL           => 0,
        -LANGUAGE           => 'en',         # Language to use for default messages
        -TITLE              => 'Quick Data',
        -HEADER             => header . 
                               start_html( 
                                   '-title' => 'Quick Data', 
                                   -BGCOLOR => '#FFCAFF',
                                   ) . 
                               h3( 'Quick Data' ), 
        -FOOTER             => hr . end_html,
        -SIZE               => undef,
        -MAXLENGTH          => undef,
        -ROWS               => undef,
        -COLUMNS            => undef,
        -INITIAL_ACTION     => 'find', # or 'list'
        -FORM_BG_COLOUR     => '#FFCAFF', # or named colour, e.g. 'BLUE'
        -DEL_HEAD_COLOUR    => '#E6BEFF',
        -DEL_FIELD_COLOUR   => '#FFE0E0',
        -DEL_VALUE_COLOUR   => '#FFA9A9',
        -LIST_HEAD_COLOUR   => '#E6BEFF',
        -LIST_BAND1_COLOUR  => '#FAFAFA',
        -LIST_BAND2_COLOUR  => '#EDEDED',
        -ACTION_COLOUR      => 'BLUE',
        -ERR_COLOUR         => 'GREEN',
        -FAIL_COLOUR        => 'RED',
        -SQL_COLOUR         => 'DARKBLUE',
        -TABLE              => undef,
        -KEYFIELD           => undef,
        -INITIAL_ORDERBY    => undef,
        -FIELDS             => undef,
        @_,
    ) ;

    die "Must specify a tablename\n" unless $Record{-TABLE} ;
    die "Must specify a keyfield\n"  unless $Record{-KEYFIELD} ;
    die "Must specify the fields\n"  unless $Record{-FIELDS} ;

    $Record{-INITIAL_ACTION} = $Record{-INITIAL_ACTION} eq 'list' ?
                                   $LIST : $FIND ;

    push @{$Record{-FIELDS}}, { -LABEL => $ACTION, -TYPE => 'hidden' } ;

    if( not param( $ACTION ) ) {
        param( $ACTION, param( $ADD    ) ) if param( $ADD ) ;
        param( $ACTION, param( $DELETE ) ) if param( $DELETE ) ;
        param( $ACTION, param( $EDIT   ) ) if param( $EDIT ) ;
        param( $ACTION, param( $FIND   ) ) if param( $FIND ) ;
        param( $ACTION, param( $LIST   ) ) if param( $LIST ) ;
        param( $ACTION, param( $REMOVE ) ) if param( $REMOVE ) ;
        param( $ACTION, param( $SEARCH ) ) if param( $SEARCH ) ;
        param( $ACTION, param( $UPDATE ) ) if param( $UPDATE ) ;
    }

    $Action = param( $ACTION )            || $Record{-INITIAL_ACTION} ;  
    $ID     = param( $Record{-KEYFIELD} ) || '' ; 

    for( my $i = 0 ; $i <= $#{$Record{-FIELDS}} ; $i++ ) {
        # Set any -DB_* defaults here.
        ${$Record{-FIELDS}}[$i]->{-DB_QUOTE}  = 1  
        unless defined ${$Record{-FIELDS}}[$i]->{-DB_QUOTE} ; 

        ${$Record{-FIELDS}}[$i]->{-DB_ALIGN}  = '' 
        unless defined ${$Record{-FIELDS}}[$i]->{-DB_ALIGN} ; 

        ${$Record{-FIELDS}}[$i]->{-DB_VALIGN} = '' 
        unless defined ${$Record{-FIELDS}}[$i]->{-DB_VALIGN} ; 

        ${$Record{-FIELDS}}[$i]->{-DB_PREFIX} = '' 
        unless defined ${$Record{-FIELDS}}[$i]->{-DB_PREFIX} ; 
    }

    if( $Action eq $ADD or $Action eq $EDIT or $Action eq $UPDATE ) {
        &_add_or_edit_record ;
    }
    elsif( $Action eq $DELETE ) {
        &_delete_record ; # Offers confirmation option which leads to remove
    }
    elsif( $Action eq $REMOVE ) {
        &_on_valid_form ;
    }
    elsif( $Action eq $FIND ) {
        &_find_records() ; # Offers search option which leads to list
    }
    elsif( $Action eq $LIST or $Action eq $SEARCH ) {
        &_list_records() ; # () ensure no spurious parameter passing.
    }

    &_quit ;
}


sub _quit {
    $DB_HANDLE->disconnect() ;
}

     
sub _on_valid_form {

    my $result = p( "Action is $Action, ID is $ID" ) ; # DEBUG

    if( $Action eq $ADD ) {
        $result = &_insert_record ; 
    }
    elsif( $Action eq $REMOVE and $ID ) {
        $result = &_execute_sql( 
                    "DELETE FROM $Record{-TABLE} WHERE $Record{-KEYFIELD} = '$ID'",
                    p( colour( $Record{-ACTION_COLOUR}, 
                       "Record $ID deleted successfully" ) )
                    ) ;
    }
    elsif( $Action eq $UPDATE ) {
        $result = &_update_record ;
    }

    if( $Record{-INITIAL_ACTION} eq $LIST ) {
        &_list_records( $result ) ;
    }
    else {
        &_find_records( $result ) ;
    }
}


sub _execute_sql {
    my( $stmt, $result ) = @_ ;

    $result = p( "Executed:<BR>", 
                 tt( colour( $Record{-SQL_COLOUR}, $stmt ) ) ) . $result 
    if $Record{-SHOW_SQL} ;

    $@ = undef ;
    eval {
        $DB_HANDLE->do( $stmt ) ; 
    } ;
    $result = &_fail_form( "$@ <P>Executed:<BR>$stmt" ) if $@ ;

    $result ;
}


sub _fail_form {
    my $err = shift || $DBI::errstr ;

    h3( colour( $Record{-FAIL_COLOUR}, "$Record{-TITLE} - Action Failed" ) ) .
    p(  colour( $Record{-ERR_COLOUR}, $err ) ) .
    p( qq{<A HREF="$URL">$Record{-TITLE}</A>} )
    ;
}


sub _add_or_edit_record {

    my $result = '' ;
    my @field  = @{$Record{-FIELDS}} ;
    CGI::delete( $ACTION ) ;
    CGI::delete( $ADD ) ;
    my $check  = 1 ;
    my $button = $ADD ;
    my $add = $Action eq $ADD ? '' : qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> } ;

    if( param( $UPDATE ) or $Action eq $EDIT ) { 
        $button = $UPDATE ;
        push @field, { -name => $ORIGINALID, -TYPE => 'hidden', -value => $ID } ;
    }
    if( $Action eq $EDIT ) {
        $check  = 0 ;
        $result = &_retrieve_record ;
        CGI::delete( $EDIT ) ;
        push @field, { -name => $UPDATE, -TYPE => 'hidden' } ; 
    }

    my $delete = ( $ID and ( $Action ne $ADD ) ) ? 
                    qq{<A HREF="$URL?$ACTION=$DELETE\&ID=$ID">$DELETE</A> } :
                    '' ;

    my $title = $Action eq $UPDATE ? $EDIT : $Action ;
    my $header = $Record{-HEADER} ;
    $header =~ s/<:ACTION:>/$title/go ;

    show_form(
        -LANGUAGE  => $Record{-LANGUAGE},
        -TITLE     => $Record{-TITLE},
        -HEADER    => $header . $result .
                      p( $add .  $delete .
                        qq{<A HREF="$URL?$ACTION=$FIND">$FIND</A> } . 
                        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>} ),
        -FOOTER    => p( $add .  $delete .
                        qq{<A HREF="$URL?$ACTION=$FIND">$FIND</A> } . 
                        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>} ) .
                     $Record{-FOOTER},
        -ACCEPT    => \&_on_valid_form,
        -CHECK     => $check,
        -SIZE      => $Record{-SIZE},
        -MAXLENGTH => $Record{-MAXLENGTH},
        -ROWS      => $Record{-ROWS},
        -COLUMNS   => $Record{-COLUMNS},
        -FIELDS    => \@field,
        # Should delete DB_* keys from each @field record - but no need since
        # show_form and CGI.pm will ignore what they don't recognise.
        -BUTTONS   => [ { -name => $button } ], 
        ) ;
}


sub _delete_record {

    my $header = $Record{-HEADER} ;
    $header =~ s/<:ACTION:>/Delete/go ;

    print
        $header,
        p( qq{<A HREF="$URL?$ACTION=$EDIT\&ID=$ID">$EDIT</A>\&nbsp;\&nbsp;},
        qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> } . 
        qq{<A HREF="$URL?$ACTION=$FIND">$FIND</A> } . 
        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>} ),
        qq{<TABLE BORDER="1" CELLSPACING="0">},
        qq{<TR BGCOLOR="$Record{-DEL_HEAD_COLOUR}">},
        th( 'Field' ), th( 'Value' ),
        "</TR>",
        ;

    print &_retrieve_record ;

    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        next if $fieldref->{-TYPE} and 
                ( $fieldref->{-TYPE} eq 'hidden' or 
                  $fieldref->{-TYPE} eq 'submit' ) ;
        my $field = param( $fieldref->{-LABEL} ) ;
        if( my $html = $fieldref->{-DB_HTML} and $field ) {
            $field = &_render_field( $field, $html ) ;
        }
        $field ||= '&nbsp;' ;
        my $align    = qq{ ALIGN="$fieldref->{-DB_ALIGN}"} ;
        my $valign   = qq{ VALIGN="$fieldref->{-DB_VALIGN}"} ;
        my $currency = $fieldref->{-DB_PREFIX} ;
        print qq{<TR><TD BGCOLOR="$Record{-DEL_FIELD_COLOUR}">} .
              qq{$fieldref->{-LABEL}</TD>} .
              qq{<TD BGCOLOR="$Record{-DEL_VALUE_COLOUR}"$align>} .
              qq{$currency$field</TD></TR>} ;
    }

    print
        "</TABLE>",
        p( qq{<A HREF="$URL?$ACTION=$REMOVE\&ID=$ID">Confirm Delete</A>} 
        . '&nbsp;&nbsp;' .
        qq{<A HREF="$URL?$ACTION=$EDIT\&ID=$ID">$EDIT</A>} ),
        p( qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> } . 
        qq{<A HREF="$URL?$ACTION=$FIND">$FIND</A> } . 
        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>} ),
        $Record{-FOOTER},
        ;
}


sub _find_records {
    my $result = shift || '' ;

    my @comparison = ( 'Any', 'Like', 'Not Like', 
                       '=', '!=', '<=', '<', '>', '>=', 
                       'Is Null', 'Is Not Null' ) ;
    my @connector  = ( 'And', 'Or' ) ;

    my $header = $Record{-HEADER} ;
    $header =~ s/<:ACTION:>/Find/go ;

    print
        $header,
        $result,
        qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> }, 
        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>},
        start_form,
        qq{<TABLE BORDER="0" CELLSPACING="0">},
        Tr( th( [ "Field", "\L\u$COMPARISON", "\L\u$VALUE", "\L\u$CONNECTOR" ] ) ),
        ;
   
    my @orderby ;
    my $i = -1 ;
    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        $i++ ;
        next if $fieldref->{-TYPE} and 
                ( $fieldref->{-TYPE} eq 'hidden' or 
                  $fieldref->{-TYPE} eq 'submit' ) ;
        push @orderby, $fieldref->{-LABEL} ;
        print 
            qq{<TR><TD>$fieldref->{-LABEL}</TD><TD>},
            scrolling_list(
                -name     => "$COMPARISON$i",
                -size     => 1,
                '-values' => \@comparison,
            ),
            qq{</TD><TD>},
            textfield( "$VALUE$i" ),
            qq{</TD><TD>},
            scrolling_list(
                -name     => "$CONNECTOR$i",
                -size     => 1,
                '-values' => \@connector,
            ),
            qq{</TD></TR>},
            ;
    }

    print 
        qq{<TR><TD><I>Order by</I></TD><TD COLSPAN="3">},
        scrolling_list(
            -name     => $ORDERBY,
            -size     => 1,
            '-values' => \@orderby,
        ),
        "</TD><TD></TD></TR></TABLE>", 
        submit( $SEARCH ), end_form, 
        qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> } .
        qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>},
        $Record{-FOOTER} ;
}


sub _list_records {
    my $result = shift || '' ;

    my @label = &_get_labels ;
    my $where = $Action eq $SEARCH ? &_get_where : param( $WHERE ) || '' ;

    my $header = $Record{-HEADER} ;
    $header =~ s/<:ACTION:>/List/go ;

    print $header, $result ;

    my $order_by = &_label2fieldname( param( $ORDERBY ) ) || 
                   $Record{-INITIAL_ORDERBY} ;
    my $stmt     = "SELECT " ;
    {
        local $^W = 0 ;
        # Some are bound to be undefined.
        $stmt .= join ", ", map { $_->{-DB_NAME} } @{$Record{-FIELDS}} ;
    }
    chop $stmt ; chop $stmt ;
    $stmt .= " FROM $Record{-TABLE} " ;
    $stmt .= "WHERE $where "      if $where ;
    $stmt .= "ORDER BY $order_by" if $order_by ;
    print p( "Executed:<BR>", tt( colour( $Record{-SQL_COLOUR}, $stmt ) ) ) 
    if $Record{-SHOW_SQL} ;

    print
        qq{<TABLE BORDER="1" CELLSPACING="0">},
        qq{<TR BGCOLOR="$Record{-LIST_HEAD_COLOUR}">},
        qq{<TD ALIGN="CENTER"><A HREF="$URL?$ACTION=$ADD">$ADD</A></TD>},
        qq{<TD ALIGN="CENTER"><A HREF="$URL?$ACTION=$FIND">$FIND</A></TD>},
        th( [ map { qq{<A HREF="$URL?$ACTION=$LIST\&} . #"
                    qq{$ORDERBY=} . uri_escape( $_ ) . 
                    qq{\&$WHERE=} . uri_escape( $where, 
                        q{\x00-\x20"'#%;=<>?{}|\\^~`\[\]\x7F-\xFF} ) . #"
                    qq{">} . encode_entities( $_ ) . "</A>" #"
                   } @label ] ),
        "</TR>",
        ;

    my $matches  = 0 ;
    my @colour   = ( qq{ BGCOLOR="$Record{-LIST_BAND1_COLOUR}"}, 
                     qq{ BGCOLOR="$Record{-LIST_BAND2_COLOUR}"} ) ;
    my $colour   = $colour[0] ;
    $@           = undef ;
    eval {
        my $sth = $DB_HANDLE->prepare( $stmt ) ;
        $sth->execute() ;
        while( my @field = $sth->fetchrow_array ) {
            last unless $field[0] ;
            my $id = $field[0] ;
            $matches++ ;
            print "<TR$colour>" ;
            $colour = ( $colour eq $colour[0] ) ? $colour[1] : $colour[0] ;
            print
                qq{<TD ALIGN="CENTER">},
                qq{<A HREF="$URL?$ACTION=$EDIT\&ID=$id">$EDIT</A></TD>}, 
                qq{<TD ALIGN="CENTER">},
                qq{<A HREF="$URL?$ACTION=$DELETE\&ID=$id">$DELETE</A></TD>} ;
            for( my $i = 0 ; $i < $#{$Record{-FIELDS}} ; $i++ ) {
                my $field = $field[$i] ;
                if( my $html = ${$Record{-FIELDS}}[$i]->{-DB_HTML} and $field ) {
                    $field = &_render_field( $field, $html ) ;
                }
                my $align    = qq{ ALIGN="${$Record{-FIELDS}}[$i]->{-DB_ALIGN}"} ;
                my $valign   = qq{ VALIGN="${$Record{-FIELDS}}[$i]->{-DB_VALIGN}"} ;
                my $currency = ${$Record{-FIELDS}}[$i]->{-DB_PREFIX} ;
                if( not $field ) {
                    $currency = '' ;
                    $field = '&nbsp;' ;
                }
                print "<TD$align>$currency$field</TD>" ;
            }
            print "</TR>" ;
        }
        print '</TABLE>' ;
        print p( colour( $Record{-ERR_COLOUR}, "No matches found" ) ) 
        unless $matches ;
        $sth->finish() ;
    } ;
    if( $@ ) { 
        print '</TABLE>' . &_fail_form( "$@ <P>Executed:<BR>$stmt" ) ;
    }
    else {
        print '</TABLE>' ;
    }
    my $s = $matches == 1 ? '' : 's' ;
    print p( "$matches record$s\&nbsp;\&nbsp;" . 
             qq{<A HREF="$URL?$ACTION=$ADD">$ADD</A> } .
             qq{<A HREF="$URL?$ACTION=$FIND">$FIND</A> } .
             qq{<A HREF="$URL?$ACTION=$LIST">$LIST</A>} 
           ), $Record{-FOOTER} ;
}


sub _insert_record {

    my $stmt = "INSERT INTO $Record{-TABLE} (" ; 
    {
        local $^W = 0 ;
        # Some are bound to be undefined.
        $stmt .= join ", ", map { $_->{-DB_NAME} } @{$Record{-FIELDS}} ;
    }
    chop $stmt ; chop $stmt ;
    $stmt .= " ) VALUES ( " ;
    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        next if $fieldref->{-TYPE} and 
                ( $fieldref->{-TYPE} eq 'hidden' or 
                  $fieldref->{-TYPE} eq 'submit' ) ;
        my $value = param( $fieldref->{-LABEL} ) ;
        $value =~ s/\n\r/ /go ;
        my $quote = $fieldref->{-DB_QUOTE} ? "'" : '' ;
        $stmt .= "$quote$value$quote, " ;
    }
    substr( $stmt, -2, 2 ) = " )" ;

    &_execute_sql( $stmt,  
                  p( colour( $Record{-ACTION_COLOUR}, 
                             "Record $ID added successfully" ) ) ) ;
}


sub _update_record {

    my $id   = param( $ORIGINALID ) ;
    my $stmt = "UPDATE $Record{-TABLE} SET" ;
    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        next if ( ( $fieldref->{-TYPE} and 
                    ( $fieldref->{-TYPE} eq 'hidden' or 
                      $fieldref->{-TYPE} eq 'submit' ) ) or
                ( $fieldref->{-DB_NAME} eq $Record{-KEYFIELD} ) ) ;
        my $value = param( $fieldref->{-LABEL} ) ;
        $value =~ s/\n\r/ /go ;
        my $quote = $fieldref->{-DB_QUOTE} ? "'" : '' ;
        $stmt .= " $fieldref->{-DB_NAME} = $quote$value$quote, " ; 
    }
    chop $stmt ; chop $stmt ;
    $stmt .= " WHERE $Record{-KEYFIELD} = '$id'" ;
    
    &_execute_sql( $stmt,
                  p( colour( $Record{-ACTION_COLOUR}, 
                             "Record $id updated successfully" ) ) ) ;
}


sub _retrieve_record {

    my $stmt = "SELECT " ;
    {
        local $^W = 0 ;
        # Some are bound to be undefined.
        $stmt .= join ", ", map { $_->{-DB_NAME} } @{$Record{-FIELDS}} ;
    } 
    chop $stmt ; chop $stmt ;
    $stmt .= " FROM $Record{-TABLE} WHERE $Record{-KEYFIELD} = '" .
               param( &_fieldname2label( $Record{-KEYFIELD} ) ) . "'" ;
    my $result ;
    $result = p( "Executed:<BR>", colour( $Record{-SQL_COLOUR}, $stmt ) ) 
    if $Record{-SHOW_SQL} ;

    my @field ;
    eval {
        my $sth = $DB_HANDLE->prepare( $stmt ) ;
        $sth->execute() ;
        @field = $sth->fetchrow_array ; 
    } ;
    if( $@ ) {
        $result .= &_fail_form( "$@ <P>Executed:<BR>$stmt" ) ; 
    }
    else {
        foreach my $label ( &_get_labels ) {
            param( $label, shift @field ) ;
        }
    }

    $result ;
}


sub _get_where {

    my $where  = '' ;
    my $excess = '' ;

    my $i = -1 ;
    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        $i++ ;
        next if $fieldref->{-TYPE} and 
                ( $fieldref->{-TYPE} eq 'hidden' or 
                  $fieldref->{-TYPE} eq 'submit' ) ;
                  
        my $comparison = uc param( "$COMPARISON$i" ) || 'ANY' ;
        next if $comparison eq 'ANY' ;

        my $field     = $fieldref->{-DB_NAME} ;
        my $value     = param( "$VALUE$i" )      || '' ;
        my $connector = uc param( "$CONNECTOR$i" ) || '' ;
        my $quote     = $fieldref->{-DB_QUOTE} ? "'" : '' ;

        if( $comparison =~ /NULL/o ) {
            $where .= "$field $comparison $connector " ;
        }
        else {
            $where .= "$field $comparison $quote$value$quote $connector " ;
        }
        $excess = $connector ;
    }

    $where =~ s/(?:AND|OR) $//o ;

    $where ;
}


sub _label2fieldname {
    my $label = shift ;
    my $fieldname ;

    local $^W = 0 ; # Despite the next we still get undefineds!
    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        next unless ( defined $fieldref->{-LABEL} and 
                      defined $fieldref->{-DB_NAME} ) ;
        $fieldname = $fieldref->{-DB_NAME}, last 
        if $label eq $fieldref->{-LABEL} ;
    }

    $fieldname ;
}


sub _fieldname2label {
    my $fieldname = shift ;
    my $label ;


    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        next unless ( defined $fieldref->{-LABEL} and 
                      defined $fieldref->{-DB_NAME} ) ;
        $label = $fieldref->{-LABEL}, last 
        if $fieldname = $fieldref->{-DB_NAME} ;
    }

    $label ;
}


sub _render_field {
    my( $field, $html ) = @_ ;

    if( $html eq 'mailto' or $html eq 'email' ) {
        $field = qq{<A HREF="mailto:$field">$field</A>} ;
    }
    elsif( $html eq 'url' or $html eq 'web' ) {
        my $protocol = $field =~ m,^(?:http|ftp|gopher|wais|/), ? 
                            '' : 'http://' ;
        $field = qq{<A HREF="$protocol$field">$field</A>} ;
    }
    elsif( $html eq 'b' or $html eq 'bold' ) {
        $field = qq{<B>$field</B>} ;
    }
    elsif( $html eq 'i' or $html eq 'italic' ) {
        $field = qq{<I>$field</I>} ;
    }
    elsif( $html eq 'bi' or $html eq 'bolditalic' ) {
        $field = qq{<B><I>$field</I></B>} ;
    }
    elsif( $html eq 'tt' or $html eq 'fixed' ) {
        $field = qq{<TT>$field</TT>} ;
    }
    elsif( $html =~ /^h([1-6])$/o ) {
        $field = qq{<H$1>$field</H$1>} ;
    }

    $field ;
}

 
sub _get_labels {
    my @label ;

    foreach my $fieldref ( @{$Record{-FIELDS}} ) {
        push @label, $fieldref->{-LABEL} 
        if $fieldref->{-LABEL} and 
           ( ( not defined $fieldref->{-TYPE} ) or
             ( $fieldref->{-TYPE} ne 'hidden' and
               $fieldref->{-TYPE} ne 'submit' ) ) ;
    }

    @label ;
}


1 ;


__END__


=head1 NAME

CGI::QuickData - Perl module to provide quick CGI forms for database tables. 

=head1 SYNOPSIS

NB This is alpha code - it is fully functional but I<not> feature-complete.

There is no documentation - however a working example, C<example1> is provided
for the time being.

=head1 DESCRIPTION

To follow. Very similar to QuickForm - builds upon it, but with more options.

=head1 BUGS

Incomplete.

=head1 AUTHOR

Mark Summerfield. I can be contacted as <summer@chest.ac.uk> -
please include the word 'quickdata' in the subject line.

=head1 COPYRIGHT

Copyright (c) Mark Summerfield 1999. All Rights Reserved.

This module may be used/distributed/modified under the LGPL.

=cut

