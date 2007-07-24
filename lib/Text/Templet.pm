# Copyright (c) 2004, 2005, 2006 Denis Petrov
# $Id: Templet.pm,v 2.8 2007/07/23 22:30:22 cvs Exp $
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Text::Templet Template Processor
#
# Text::Templet Home: http://www.denispetrov.com/magic/

use 5.006;
use strict;
use warnings;

package Text::Templet;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    ($VERSION) = '$Revision: 2.8 $' =~ /\$Revision: (\S+)/;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &Templet );
    %EXPORT_TAGS = ( );
    @EXPORT_OK   = qw( $HeaderCallback );
}

### variable names are strange to reduce the risk of them being used in a template

our @_tpl_parsed;

our $_isect;
our $_nsect;

our @_tpl_warning = ();

our %_labels; # label section numbers

### reference to the output function and to the output buffer
our $_outf;
our $_outt;

our $_label_regexp = "\\*?[a-zA-z_][a-zA-z0-9_]*";

our $_first_outf;
our $HeaderCallback = sub {};

our $_use_package;

sub _tpl_warn
{
    push @_tpl_warning, $_[0];
}

# parameters: section type ('code' or 'text' or 'label')
sub _print_tpl_warning
{
   my $lc = &_count_lines();
   my (undef,$fn,$fl) = caller(1);
   print STDERR "Templet warning: $fn:$fl, $_[0] section beginning at line $lc(".($fl+$lc).")\n";
   foreach(@_tpl_warning)
   {
     print STDERR $_ . "\n";
   };
   @_tpl_warning = ();
}

# \@_tpl_parsed, $currentpos
sub _count_lines
{
  my $count = 1; # first line
  for ( my $_i = 0; $_i < $_isect; $_i++ )
  {
    $count += scalar($_tpl_parsed[$_i] =~ tr/\n//);
  }
  # if the current section follows a code or label section ending in a newline, it will appear
  # starting on the same line as that code section, which is confusing
  # so treat this newline as part of preceding code section, i.e. increase line number by 1
  $count++ if $_tpl_parsed[$_isect] =~ /^\s*\n/;
  return $count;
}

# jump to a label
sub _jump_to($)
{
  my ($lname) = @_;
  if ( exists $_labels{$lname} )
  {
    $_isect = $_labels{$lname};
  }
  else
  { #trace labels forward
    my $j;
    my $found_label = undef;
    for ( $j = $_isect+1; $j < $_nsect; $j++ )
    {
      if ( $_tpl_parsed[$j] =~ /<%($_label_regexp)%>/ )
      {
        if ( exists($_labels{$1}) && $_labels{$1} != $j )
        {
           push @_tpl_warning, "Found duplicate label '$1', it has been ignored";
           &_print_tpl_warning('label');
        }
        else
        {
          $_labels{$1} = $j;
        }
        if ( $1 eq $lname )
        {
          $_isect = $j;
          $found_label = 1;
          last;
        }
      }
    }
    if ( !$found_label )
    {
      push @_tpl_warning, "A template code section returned label '$lname'"
                      . " which does not exist in the template";
      &_print_tpl_warning('code');

      return undef;
    }
  }
  return 1;
}


sub Use($)
{
  $_use_package = $_[0];
  eval("use $_use_package;");
}


sub Templet
{
  my ($_caller_package,undef,undef) = caller;

  ### Make Templet re-entrant by saving values of package variables
  local(@_tpl_parsed,$_isect,$_nsect,%_labels,@_tpl_warning,$_outf,$_outt,$_first_outf);

  $_outt = '';
  ### Return processed template in non-void context, otherwise print it
  $_outf = defined(wantarray) ?
         sub{&$HeaderCallback(),$_first_outf = 0 if $_first_outf;$_outt .= $_[0]}
       : sub{&$HeaderCallback(),$_first_outf = 0 if $_first_outf;print @_};

  $_use_package = $_[1] || $_use_package || $_caller_package;

  $_first_outf = 1;

  @_tpl_parsed = ('<%_%>' . $_[0] . '<%END%>') =~ /(<%.+?(?=%>)%>)(.*?)(?=<%|$)/gs;

  $_isect = 0; # template section iterator
  $_nsect = scalar(@_tpl_parsed); # number of sections
  for ( $_isect = 0; $_isect < $_nsect; $_isect++ )
  {
    my $_sect_text = $_tpl_parsed[$_isect];
    if ( $_sect_text =~ /<%($_label_regexp)%>/ )
    {
      if ( exists($_labels{$1}) && $_labels{$1} != $_isect )
      {
         push @_tpl_warning, "Found duplicate label '$1', it has been ignored";
         &_print_tpl_warning('label');
      }
      else
      {
        $_labels{$1} = $_isect;

        if ( substr($1,0,1) eq '*' )
        {
          # skip to the label with the same name without asterisk
          _jump_to(substr($1,1));
        }
      }
    }
    elsif ( $_sect_text =~ /<%(.+)%>/s )
    {
      my $_save_sig = $SIG{__WARN__};
      $SIG{__WARN__} = \&_tpl_warn;
      my $_result = eval("package $_use_package;".$1);
      $SIG{__WARN__} = $_save_sig;
      &_print_tpl_warning('code') if scalar(@_tpl_warning) > 0;
      if ( !defined($_result) )
      {
          if ( $@ )
          {
              push @_tpl_warning, $@;
              &_print_tpl_warning('code');
              print STDERR "Processing of this template has stopped.\n";
              die $@;
          }
          # else there's no error, just discard the undef and move on
      }
      elsif ( $_result =~ /$_label_regexp/ )
      {
        _jump_to($_result);
      }
    }
    elsif ( $_sect_text ne '' )
    {
      $_sect_text =~ s/\"/\\\"/g;
      my $_save_sig = $SIG{__WARN__};
      $SIG{__WARN__} = \&_tpl_warn;
      my $_result = eval("package $_use_package;"."\"".$_sect_text."\"");
      $SIG{__WARN__} = $_save_sig;
      if ( !defined($_result) )
      {
          if ( $@ )
          {
              push @_tpl_warning, $@;
              &$_outf( @_tpl_warning );
              &_print_tpl_warning('text');
          }
      }
      else
      {
          &_print_tpl_warning('text') if scalar(@_tpl_warning) > 0;
          &$_outf( $_result );
      }
    }
  }


 # use Data::Dumper;
 # print Dumper(\@_tpl_parsed);
 # print Dumper(%_labels);


  return $_outt;
}


1;
=pod

=head1 NAME

Text::Templet - template processor built using Perl's eval()

=head1 SYNOPSIS

B<Iterating through a list>

 use Text::Templet;
 use vars qw( $dataref $counter );
 $dataref = ["Money For Nothing","Communique","Sultans Of Swing"];

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% $counter = -1 %>
 <%SONG_LIST%>
 <% $counter++; return "SONG_LIST_END" if $counter >= scalar(@$dataref); '' %>
 <div>
 $counter: $dataref->[$counter]
 </div>
 <%"SONG_LIST"%><%SONG_LIST_END%>
 </body>
 EOT
 );

B<Iterating through a list using asterisk label>

 use Text::Templet;
 use vars qw( $dataref $counter );
 $dataref = ["Money For Nothing","Communique","Sultans Of Swing"];

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% $counter = -1 %>
 <%SONG_LIST%><% $counter++; return "*SONG_LIST" if $counter >= scalar(@$dataref); '' %>
 <div>
 $counter: $dataref->[$counter]
 </div>
 <%*SONG_LIST%>
 </body>
 EOT
 );

B<Conditional inclusion>

 use Text::Templet;
 use vars qw($super_user);
 $super_user = 1;

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% "SKIP_CP" unless $super_user %>
 Admin Options: <a href="control_panel.pl">Control Panel</a>
 <%SKIP_CP%>
 </body>
 EOT
 );

B<Alternative inclusion>

 use Text::Templet;
 use vars qw($super_user);
 $super_user = 1;

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% "*SKIP_CP" unless $super_user %>
 Admin Options: <a href="control_panel.pl">Control Panel</a>
 <%*SKIP_CP%>
 No Admin options available.
 <%SKIP_CP%>
 </body>
 EOT
 );

B<Switch-like construct>

 use Text::Templet;
 use vars qw($super_user);
 $select = 1;

 $select = 0 if ( int($select) < 0 or int($select) > 2 );

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% "*SEL".int($select) %>
 <%*SEL0%>
 Select is 0
 <%SEL0%>
 <%*SEL1%>
 Select is 1
 <%SEL1%>
 <%*SEL2%>
 Select is 2
 <%SEL2%>
 </body>
 EOT
 );

B<Calling a Perl subroutine from inside a template>

 use Text::Templet;

 sub hello_world()
 {
     print "Hello, World!";
 }

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% hello_world(); '' %>
 </body>
 EOT
 );

B<Using subroutine return value as a label>

 use Text::Templet;

 sub give_me_label()
 {
     return 'L1';
 }

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <% give_me_label(); %>
 This text will be omitted.
 <%L1%>
 </body>
 EOT
 );

B<A simple form>

 use Text::Templet;
 use CGI;
 use vars qw( $title $desc );
 $title = "Title here!";
 $desc = "Description Here!";
 $title = &CGI::escapeHTML($title||'');
 $desc = &CGI::escapeHTML($desc||'');

 Templet(<<'EOT'
 Content-type: text/html

 <body>
 <form method="POST" action="submit.pl">
 <input name="title" size="60" value="$title">
 <textarea name="desc" rows="3" cols="60">$desc</textarea>
 <input type="submit" name="submit" value="Submit">
 </form>
 </body>
 EOT
 );

B<Sending output to a disk file>

 use Text::Templet;
 local *FILE;
 open( FILE, '>page.html' ) or warn("Unable to open file page.html: $!"), return 1;
 my $saved_stdout = select(*FILE);

 Templet(<<'EOT'
 <body>
 Hello, World!
 </body>
 EOT
 );

 select($saved_stdout);
 close FILE;

B<Saving output in a variable>

 use Text::Templet;

 my $output = Templet(<<'EOT'
 <body>
 Hello, World!
 </body>
 EOT
 );

 print $output;

B<Includes>

 use Text::Templet;
 use vars qw($title $text);
 $title = 'Page Title';
 $text = 'Page Body';

 sub header
 {
   Templet('<html><head><title>$title</title></head><body>');
   ''
 }

 sub footer
 {
   Templet('</body></html>');
   ''
 }


 Templet(<<'EOT'
 Content-type: text/html

 <% header() %>
 <h1>$title</h1>
 <div>
 $text
 </div>
 <% footer() %>
 EOT
 );

B<A structured application>

 use CGI;
 use Text::Templet;
 use vars qw($body_sub $title);

 $Q = new CGI;

 if ( $Q->param('p') eq 'page1' )
 {
   $title = 'Page 1';
   $body_sub = sub
   {
     Templet('Page 1');
   }
 }
 elseif ( $Q->param('p') eq 'page2' )
 {
   $title = 'Page 2';
   $body_sub = sub
   {
     Templet('Page 2');
   }
 }
 else
 {
   $title = 'Default Page';
   $body_sub = sub
   {
     Templet('Default Page');
   }
 }

 Templet(<<'EOT'
 Content-type: text/html

 <html><head><title>$title</title></head>
 <body>
 <h1>$title</h1>
 <div>
 <% &$body_sub(); '' %>
 </div>
 </body></html>
 EOT
 );

B<Using $Text::Templet::HeaderCallback>

 use CGI;
 use Text::Templet;
 use vars qw($redirect $title);

 $Q = new CGI;

 $Text::Templet::HeaderCallback = sub {print "Content-type: text/html\r\n\r\n"};

 $redirect = 'http://www.denispetrov.com/';
 $title = 'This page is never seen because it always redurects the browser to www.denispetrov.com';

 Templet(<<'EOT'
 <% $Q->print($Q->redirect(-uri=>$redirect)),exit() if $redirect; '' %>
 <html><head><title>$title</title></head>
 <body>
 <h1>$title</h1>
 </body></html>
 EOT
 );

B<Using &Text::Templet::Use>

File Module.pm:

 package Module;

 use vars qw($title);

 $title = 'Page Title';

File script.pl:

 use lib qw(.);
 use Text::Templet;

 $Text::Templet::HeaderCallback = sub {print "Content-type: text/html\r\n\r\n"};

 Templet(<<'EOT'
 <% Text::Templet::Use("Module");'' %>
 <html><head><title>$title</title></head>
 <body>
 <h1>$title</h1>
 </body></html>
 EOT
 );

=head1 DESCRIPTION

C<Text::Templet> is a Perl module implementing a very efficient
and fast template processor that allows you to embed Perl
variables and snippets of Perl code directly into HTML, XML or any
other text. C<Text::Templet> is unique in that it employs Perl's
C<eval()> function for features that other template systems
implement using regular expressions, introducing a whole new
syntax, with complexity proportional to the system's
sophistication. C<Text::Templet> uses Perl syntax for all its
functionality, which greatly simplifies and speeds up processing
of the template.

In the examples above the template text is embedded into the Perl
code, but it could just as easily be loaded from a file or a
database. C<Text::Templet> does not impose any particular
application framework or CGI library or information model on you.
You can pick any of the existing systems or integrate
C<Text::Templet> into your own.

When called, C<Templet()> applies a regular expression matching
text enclosed within C<< <% %> >> to create a list of sections.
These sections are then passed to the eval() function. Sections
containing text outside C<< <% %> >> ("Template text sections") are
wrapped into double quotes and passed to C<eval()> for variable
expansion. In void context, the value returned by the C<eval()> is
printed to the standard output, otherwise it is appended to the return
value stored in C<$_outt>.

Sections with text inside C<< <% %> >> are handled in two different
ways. If the text contains only alphanumeric characters without
spaces, and the first character is an asterisk, a letter or an underscore,
C<Text::Templet> recognizes the section as a "label", which is then
added to the internal list of labels. Labels are used to pass
template processing point to the section immediately following the
label, very similar to the way labels used in many programming
languages to move the execution point of a program.

If it is not a label, then it is a template code section, which is
passed to C<eval()> for execution as Perl code. The return value of
a code section is then used as the name of the label to jump to, allowing you to implement
loops, conditionals and any other control statements using Perl code.
A warning is produced if the label with that name is
not found in the template, and the text that does not represent a
valid label name is discarded.

When a portion of a template is contained between two labels, named identically
except the first one pre-pended with "*" (asterisk), this portion
will be skipped in the normal flow of template processing, and can
only be reached by returning the name of the label with the asterisk
from a code section. This simplifies the syntax of conditionals, switches
and other types of constructs. The following two examples are equivalent,
one is written using an asterisk label and the other is not:

 <% "*SKIP" unless $condition %>
 Text displayed when the condition is true
 <%*SKIP%>
 Text displayed when the condition is false
 <%SKIP%>

 <% "ELSE" unless $condition %>
 Text displayed when the condition is true
 <%"ELSE_END"%><%ELSE%>
 Text displayed when the condition is false
 <%ELSE_END%>

All package variables that you plan to use in the template must be
declared with C<use vars> - code and variable names embedded into
the template are evaluated in the namespace of the calling package,
but are contained in the lexical scope of C<Templet.pm>. This means that
lexical variables declared with C<my>, C<our> or C<local> are inaccessible
from "inside" the template.

The following variable names are used internally by
C<Text::Templet> and will mask variables declared in your program,
making their values inaccessible in the template: C<%_labels>,
C<@_tpl_parsed>, C<@_tpl_warning>, C<$_label_regexp>, C<$_isect>,
C<$_nsect>, C<$_sect_text>, C<$_save_sig>, C<$_outf>, C<$_outt>

=head2 FUNCTIONS

C<&Templet()>

Exported. Takes one or two arguments: first argument is the template text, second
argument is optional and contains the name of the package to use when
evaluating section text and code.

In void context, prints processing result to the default output,
otherwise accumulates it in internal variable C<$_outt> and returns
it to the caller. If a compilation error occurs in a code section of the
template, calls die() with the error code, which allows you to put Templet()
call into a try block to process compilation errors. You should check the
server's error log to find out which section it is.

C<&Text::Templet::Use()>

Accepts one argument containing the name of the package to use when evaluating
template sections. The value will be used in each call to each code and text
section to set the context for any code and variables used in the template.
This function can be called either prior to C<Templet()> call or from within
the template text, in which case the package name will be used from the code
section containing the call onwards until the end of the template
or the next call to C<Text::Templet::Use()>.

=head2 PUBLIC VARIABLES

C<$Text::Templet::HeaderCallback>

A reference to a function that sends HTTP or any other header before any
output from the template occurs. Provides a way to send redirection headers
from the template when C<Templet()> is called in void context. See
Using $Text::Templet::HeaderCallback example.

=head1 NOTES AND TIPS

=over

=item * Using interpolating quotes around the template text wreaks
havoc as variables are interpolated before C<Text::Templet> has a
chance to look at them. This is the purpose of single quotes around
EOT at the examples above - to prevent early interpolation.

=item * Warning 'Use of uninitialized value in concatenation (.) or
string at (eval ...) line x (#x)' indicates that a variable used in
the template contains an undefined value, which may happen when you
pull the data from a database and some of the fields in the
database record being queried contain NULL. This issue can be
resolved either on the data level, by ensuring that there are no
NULL values stored in the database, or on the script level by
replacing undefined values returned from the database with empty
strings. The simple form example above deals with this problem by
using C<||> operator during the call to C<&CGI::escapeHTML> to assign an
empty string to the variable if it evaluates to false.

=item * Label names are case sensitive, and there must be no spaces
anywhere between C<< <% >> and C<< %> >> for it to be interpreted as a label. All
labels in a template must have unique names.

=item * C<Text::Templet> is compatible with mod_perl. However, make
sure that each Perl function has a unique name across all scripts
on the server running mod_perl. The best way to ensure that is to
put each Perl file into its own package. Reusing function names
among different files will result in 'function reload' warnings and
functions from wrong files being called.

=item * Watch the web server's error log closely when debugging
your application. C<Text::Templet> posts a warning when there is
something wrong with the template, including the line number of the
beginning of the section where the error occurred.

=item * Call C<&$_outf()> from within C<< <% %> >> to append something
to the output: C<< <% &$_outf("foo") %> >>. This function takes one
argument and will either send it to the standard output or append it
to C<$_outt> depending on Templet's calling context.

=item * To prevent C<Text::Templet> from trying to use the result
of the processing in the template code section as a label name, add
an empty string at the end: C<< <% print "foo"; '' %> >>.

=item * Be careful not to create infinite loops in the template as
C<Text::Templet> does not check for them. I may come up with a
version specifically for debugging templates, but it is not a
priority right now.

=item * C<Text::Templet>'s version number is the CVS revision of
the file, which means some numbers may get skipped.

=item * Call Templet() from void context whenever possible to improve
performance. When called from void context all output from the template
is printed as soon as it is processed without first accumulating it
in a buffer, which saves memory and when used in a web application,
allows the browser to start rendering the processed page as soon as
the web server has accumulated enough data to send to the browser.

=back

=head1 AUTHOR

Denis Petrov <denispetrov@yahoo.com>

For more examples and support, visit Text::Templet Home at
http://www.denispetrov.com/magic/

=cut
