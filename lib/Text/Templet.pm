# Copyright (c) 2004, 2005 Denis Petrov
# $Id: Templet.pm,v 2.0 2005/07/01 20:46:02 cvs Exp $
# Distributed under the terms of the GNU General Public License
#
# Templet Template Processor
#
# Templet Home: http://www.denispetrov.com/magic/

use 5.006;
use strict;
use warnings;

package Text::Templet;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    ($VERSION) = '$Revision: 2.0 $' =~ /\$Revision: (\S+)/;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw( &Templet );
    %EXPORT_TAGS = ( );
    @EXPORT_OK   = qw( );
}

# variable names are strange to reduce the risk of them being used in a template

our @___tpl_parsed;

our $___ii;

our $___tpl_warning = '';

sub ___tpl_warn
{
    $___tpl_warning = $_[0];
}

# parameters: section type ('code' or 'text' or 'label')
sub ___print_tpl_warning
{
   my $lc = &___count_lines();
   my (undef,$fn,$fl) = caller(1);
   print STDERR "Templet warning: $fn:$fl, $_[0] section beginning at line $lc(".($fl+$lc).")\n$___tpl_warning\n";
   $___tpl_warning = '';
}

# \@___tpl_parsed, $currentpos
sub ___count_lines
{
  my $count = 1; # first line
  for ( my $_i = 0; $_i < $___ii; $_i++ )
  {
    $count += scalar($___tpl_parsed[$_i] =~ tr/\n//);
  }
  # if the current section follows a code or label section ending in a newline, it will appear
  # starting on the same line as that code section, which is confusing
  # so treat this newline as part of preceding code section, i.e. increase line number by 1
  $count++ if $___tpl_parsed[$___ii] =~ /^\s*\n/;
  return $count;
}

sub Templet
{
  my ($___caller_package,undef,undef) = caller;
  
  ### Make Templet re-entrant by saving values of package variables
  local(@___tpl_parsed,$___ii,$___tpl_warning);

  my $___label_regexp = "[a-zA-z_][a-zA-z0-9_]*";

  my %___labels; # label section numbers

  @___tpl_parsed = ('<%_%>' . $_[0] . '<%END%>') =~ /(<%.+?(?=%>)%>)(.*?)(?=<%|$)/gs;

  $___ii = 0; # template section iterator
  my $___len = scalar(@___tpl_parsed); # number of sections
  for ( $___ii = 0; $___ii < $___len; $___ii++ ) 
  {
    my $___l = $___tpl_parsed[$___ii];
    if ( $___l =~ /<%($___label_regexp)%>/ ) 
    {
      if ( exists($___labels{$1}) && $___labels{$1} != $___ii )
      {
         $___tpl_warning = "Found duplicate label '$1', it has been ignored";
         &___print_tpl_warning('label');
      }
      else
      {
        $___labels{$1} = $___ii;
      }
    }
    elsif ( $___l =~ /<%(.+)%>/s ) 
    {
      my $___save_sig = $SIG{__WARN__};
      $SIG{__WARN__} = \&___tpl_warn;
      my $___result = eval("package $___caller_package;".$1);
      $SIG{__WARN__} = $___save_sig;
      &___print_tpl_warning('code') if $___tpl_warning;
      if ( !defined($___result) )
      {
          if ( $@ )
          {
              $___tpl_warning = $@;
              &___print_tpl_warning('code');
              print STDERR "Processing of this template has stopped.\n";
              return 1;
          }
          # else there's no error, just discard the undef and move on
      }
      elsif ( $___result =~ /$___label_regexp/ ) 
      {
        if ( exists $___labels{$___result} )  
        {
          $___ii = $___labels{$___result};
        }
        else 
        { #trace labels forward
          my $j;
          my $found_label = undef;
          for ( $j = $___ii+1; $j < $___len; $j++ ) 
          {
            if ( $___tpl_parsed[$j] =~ /<%($___label_regexp)%>/ ) 
            {
              if ( exists($___labels{$1}) && $___labels{$1} != $j )
              {
                 $___tpl_warning = "Found duplicate label '$1', it has been ignored";
                 &___print_tpl_warning('label');
              }
              else
              {
                $___labels{$1} = $j;
              }
              if ( $1 eq $___result ) 
              {
                $___ii = $j;
                $found_label = 1;
                last;
              }
            }
          }
          if ( !$found_label )
          {
            $___tpl_warning = "A template code section returned label '$___result'"
                           . " which does not exist in the template";
            &___print_tpl_warning('code');
          }
        }
      }
    }
    else 
    {
      $___l =~ s/\"/\\\"/g;
      my $___save_sig = $SIG{__WARN__};
      $SIG{__WARN__} = \&___tpl_warn;
      my $___result = eval("package $___caller_package;"."\"".$___l."\"");
      $SIG{__WARN__} = $___save_sig;
      if ( !defined($___result) )
      {
          if ( $@ )
          {
              $___tpl_warning = $@;
              &___print_tpl_warning('text');
          }
      }
      else
      {
          &___print_tpl_warning('text') if $___tpl_warning;
          print( $___result );
      }
    }
  }


 # use Data::Dumper;
 # print Dumper(\@___tpl_parsed);
 # print Dumper(%___labels);


  return '';
}


1;
=pod

=head1 NAME

Text::Templet - template processor built using Perl's eval()

=head1 SYNOPSIS 

B<Iterating through a list of items>

 use Text::Templet;
 use vars qw( $dataref $counter );
 $dataref = ["Money For Nothing","Communique","Sultans Of Swing"];
 $counter = 1;

 &Templet(<<'ENDOFMAGIC'
 Content-type: text/html

 <body>
 <%SONG_LIST%>
 <div>
 $counter: $dataref->[$counter-1]
 </div>
 <% "SONG_LIST" unless $counter++ >= scalar(@$dataref) %>
 </body>
 ENDOFMAGIC
 );

B<Conditional inclusion>

 use Text::Templet;
 use vars qw($super_user);
 $super_user = 1;

 &Templet(<<'ENDOFMAGIC'
 Content-type: text/html

 <body>
 <% "SKIP_CP" unless $super_user %>
 Admin Options: <a href="control_panel.pl">Control Panel</a>
   <% "END_SKIP_CP" %>
 <%SKIP_CP%>
 No Admin options available.
 <%END_SKIP_CP%>
 </body>
 ENDOFMAGIC
 );

B<Calling a Perl subroutine from inside the template>

 use Text::Templet;
 
 sub hello_world()
 {
     print "Hello, World!";
 }

 &Templet(<<'ENDOFMAGIC'
 Content-type: text/html

 <body>
 <% &hello_world(); '' %>
 </body>
 ENDOFMAGIC
 );

B<A simple form>

 use Text::Templet;
 use CGI;
 use vars qw( $title $desc );
 $title = "Title here!";
 $desc = "Description Here!";
 $title = &CGI::escapeHTML($title||'');
 $desc = &CGI::escapeHTML($desc||'');
 
 &Templet(<<'ENDOFMAGIC'
 Content-type: text/html

 <body>
 <form method="POST" action="submit.pl">
 <input name="title" size="60" value="$title">
 <textarea name="desc" rows="3" cols="60">$desc</textarea>
 <input type="submit" name="submit" value="Submit">
 </form>
 </body>
 ENDOFMAGIC
 );

B<Redirecting processing output to a disk file>

 use Text::Templet;
 local *FILE;
 open( FILE, '>page.html' ) or warn("Unable to open file page.html: $!"), return 1;
 my $saved_output = select(*FILE);

 &Templet(<<'ENDOFMAGIC'
 <body>
 Hello, World!
 </body>
 ENDOFMAGIC
 );

 select($saved_output);
 close FILE;

=head1 DESCRIPTION

C<Text::Templet> is a Perl module implementing a very efficient and fast template processor that allows you to embed Perl variables and snippets of Perl code directly into HTML, XML or any other text. C<Text::Templet> is uniquie in that it employs Perl's eval() function for functionality that other template systems implement using regular expressions, introducing a whole new syntax, with complexity proportional to the system's sophistication. C<Text::Templet> uses Perl syntax for all its functionality, which greatly simplifies and speeds up processing of the template.

In the examples above the template text is embedded into the Perl code, but it could just as easily be loaded from a file or a database. C<Text::Templet> does not impose any particular application framework or CGI library or information model on you. You can pick any of the existing systems or integrate C<Text::Templet> into your own.

When called, C<Text::Templet> applies a regular expression matching text enclosed within C<< <% %> >> to create a list of sections. These sections are then passed to the eval() function. Secions containing text outside C<< <% %> >> ("Template text sections") are wrapped into double quotes and passed to eval() for variable expansion. The value returned by the eval() is then printed to the standard output.

Sections with text inside C<< <% %> >> are handled in two different ways. If the text contains only alphanumeric characters without spaces, and the first character is a letter or an underscore, C<Text::Templet> recognizes the section as a "label", which is then added to the internal list of labels. Labels are used to pass template processing point to the section immediately following the label, very similar to the way labels used in many programming languages to move the execution point of a program.

If it is not a label, then it is a template code section, which is passed to eval() for execution as Perl code. And here's the most important part that makes C<Text::Templet> so powerful: instead of sending the evaluation result of a code section to the output, C<Text::Templet> applies to it a regular expression matching valid label name. If it matches, C<Text::Templet> moves the template processing point to the label with that name. This allows you to easily implement loops, conditionals, switch-like constructs, display error messages, etc. A warning is produced if the label is not found in the template, and the text that does not represent a valid label name is discarded.

All package variables that you plan to use in the template must be declared with C<use vars> - code and variable names embedded into the template are evaluated in the namespace of the calling package, but each is contained in its own lexical scope. This means that lexical variables declared with my or our or local are inaccessible from "inside" the template.

=head2 EXPORTS

C<&Templet($)>

Takes template text as an argument, prints processing result to default output. Returns nonzero value if an error occured.

=head1 NOTES AND TIPS

=over

=item * Using interpolating quotes around the template text wreaks havoc as variables are interpolated before C<Text::Templet> has a chance to look at them. This is the purpose of single quotes around ENDOFMAGIC at the examples above - to prevent early interpolation.

=item * Warning 'Use of uninitialized value in concatenation (.) or string at (eval ...) line x (#x)' indicates that a variable used in the template contains an undefined value, which may happen when you pull the data from a database and some of the fields in the database record being queried contain NULL. This issue can be resolved either on the data level, by ensuring that there are no NULL values stored in the database, or on the script level by replacing undefined values returned from the database with empty strings. The last example above deals with this problem by using || operator during the call to &CGI::escapeHTML to assign an empty string to a value if it evaluates to false.

=item * Label names are case sensitive, and there must be no spaces anywhere between <% and %> for it to be interpreted as a label. All labels in a template must have unique names.

=item * C<Text::Templet> is compatible with mod_perl. However, make sure that each Perl function has a unique name across all scripts on the server running mod_perl. The best way to ensure that is to put each Perl file into its own package. Reusing function names among different files will result in 'function reload' warnings and functions from wrong files being called.

=item * Watch the web server's error log closely when debugging your application. C<Text::Templet> posts a warning when there is something wrong with the template, including the line number of the beginning of the section where the error occured.

=item * Call print() from within C<< <% %> >> to append something to the output: C<< <% print "foo" %> >>.

=item * To prevent C<Text::Templet> from trying to use the result of the processing in the template code section as a label name, add an empty string at the end: C<< <% print "foo"; '' %> >>.

=item * Be careful not to create infinite loops in the template as C<Text::Templet> does not check for them. I may come up with a version specifically for debugging templates, but it is not a priority right now.

=item * C<Text::Templet>'s version number is the CVS revision of the file, which means some numbers may be skipped.

=back

=head1 AUTHOR

Denis Petrov <denispetrov@yahoo.com>

Templet Home: http://www.denispetrov.com/magic/

=cut
