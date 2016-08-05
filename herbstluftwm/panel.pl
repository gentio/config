# Tom Hunt <tomahhunt@gmail.com>

#!/usr/bin/perl
use strict;
use warnings;
use IO::Pipe;
use Switch;

my $font_width = 6;
my $height=16;
my $separator="^fg(#ffffff)^ro(1x$height)^fg()";
my $num_monitors = `herbstclient list_monitors | wc -l`;
my $font = "-*-clean-bold-r-*-*-10-*-*-*-*-*-*-*";
my $use_key = "Mod4";
my $move_key = "Mod4-Shift";
my $use2_key = "Mod4-Alt";
my $move2_key = "Mod4-Alt-Shift";

my $acpi_on = 0;

sub get_date {
  return `date +'date ^fg(#efefef)%H:%M - ^fg(#efefef)%A - %d %B %Y'`;
}

sub date_for_dzen {
  my ($date) = @_;
  $date =~ s/date //;
  my $text="$separator^bg(#000000) $date $separator";
  my $text_only = $text;
  $text_only =~ s/\^\w+\([#\w+]*\)//g;
  my $width = (length($text_only) + 2) * $font_width;
  return "^p(_RIGHT)^p(-$width)$text^ca()";
}

my %TAGS;
sub update_status {
  my ($reason) = @_;
  if ($reason =~ /removed/) { for (keys %TAGS) { delete $TAGS{$_};} }
  for (my $mon = 0 ; $mon < $num_monitors ; $mon++) {
    my $status = `herbstclient tag_status $mon`;
    $status =~ s/^\t(.*)\n/$1/;
    my @array = split(/\t/, $status);
    my $i = 1;
    foreach my $entry (@array) {
      $TAGS{$mon}{$i++} = $entry;
    }
  }
}

sub update_tag {
  my ($reason, $monitor) = @_;

  my $tags_string = "";
  update_status($reason) if($monitor == 0);  #Only update from herbstclient once
  # draw tags
  foreach my $curr_tag (sort { $a <=> $b } keys %{$TAGS{$monitor}}) {
    my $tag_name = substr($TAGS{$monitor}{$curr_tag},1);

    switch (substr($TAGS{$monitor}{$curr_tag},0,1)) {
      case '#' { $tags_string .= "^bg(#00ff00)^fg(#000000)"; }
      case '+' { $tags_string .= "^bg(#00ff00)^fg(#000000)"; }
      case ':' { $tags_string .= "^bg(#000000)^fg(#ffffff)"; }
      case '-' { $tags_string .= "^bg(#FF0000)^fg(#000000)"; }
      case '%' { $tags_string .= "^bg(#FF0000)^fg(#000000)"; }
      case '!' { $tags_string .= "^bg(#FF0675)^fg(#000000)"; }
      case '.' { $tags_string .= "^bg(#aaaaaa)^fg(#000000)"; }
      else     { $tags_string .= "^bg()^fg()"; }
    }
    my $tag_comb = $tag_name;
    if ($curr_tag <= 10) {
      $curr_tag = 0 if ($curr_tag == 10);
      $tag_comb = "$curr_tag:$tag_name" if ($tag_name ne $curr_tag);
      if ($reason =~ /first|added|removed|renamed/) {
        system("herbstclient keybind '${use_key}-$curr_tag' use '$tag_name'");
        system("herbstclient keybind '${move_key}-$curr_tag' move '$tag_name'");
      }
    } else {
      $curr_tag = $curr_tag - 10 ;
      $tag_comb = "A:$curr_tag:$tag_name" if ($tag_name ne $curr_tag);
      if ($reason =~ /first|added|removed|renamed/) {
        system("herbstclient keybind '${use2_key}-$curr_tag' use '$tag_name'");
        system("herbstclient keybind '${move2_key}-$curr_tag' move '$tag_name'");
      }
    }
    $tags_string .= "^ca(1, herbstclient focus_monitor $monitor && herbstclient use $tag_name)";
    $tags_string .= "^ca(3, herbstclient merge_tag $tag_name)";
    $tags_string .= " $tag_comb ^ca()^ca()$separator";
  }
  return $tags_string;
}

my $pipe = IO::Pipe->new();

my $acpi_test;
if ($acpi_on == 1) {
  $acpi_test = `which acpi 2>&1`;
  if ($acpi_test =~ /which: no acpi/) {
    $acpi_test = 0;
  } else {
    my $acpi_test2 = `acpi 2>&1`;
    if ($acpi_test2 =~ /No support for device type: power_supply/) {
      $acpi_test = 0;
    } else {
      $acpi_test = 1;
    }
  }
} else {
  $acpi_test = 0;
}

my $pid_date = fork();

my $pid_acpi = 1;
if ($acpi_test == 1) {
  $pid_acpi = fork();
}

if ($pid_date == 0) { #Spawn Date Generator Child
  $pipe->writer();
  $pipe->autoflush();
  my $last_date = "";
  while (1) {
    my $date = get_date();
    if ($last_date ne $date) {
      $last_date = $date;
      print $pipe "$date\n";
    }
    sleep(5);
  }
} elsif ($pid_acpi == 0) {
  $pipe->writer();
  $pipe->autoflush();
  my $last_acpi = "";
  while (1) {
    my $acpi = `acpi`;
    chomp($acpi);
    if ($last_acpi ne $acpi) {
      $last_acpi = $acpi;
      print $pipe "$acpi\n";
    }
    sleep(5);
  }
} elsif (fork() == 0) { #Spawn Herbstclient Idle Child
  $pipe->writer();
  $pipe->autoflush();
  open (HERB,"herbstclient --idle |");
  while (<HERB>) { print $pipe $_; }
  kill 9, $pid_date;
  kill 9, $pid_acpi;
} elsif (fork() == 0) { #Spawn Dzen Child
  #Initial Data

  my $date_dzen_store = date_for_dzen(get_date());
  my $acpi_dzen_store = "";
  if ($acpi_test == 1) {
    $acpi_dzen_store = `acpi`;
    chomp($acpi_dzen_store);
    $acpi_dzen_store =~ s/Battery 0: /                /;
  }
  my %tags_dzen_store;
  for (my $mon = 0 ; $mon < $num_monitors ; $mon++) {
    $tags_dzen_store{$mon} = update_tag("tag_added", $mon);
  }

  my %dzen;
  #Spawn DZEN instances
  for (my $mon = 0 ; $mon < $num_monitors ; $mon++) {
    system("herbstclient pad $mon $height");
    my @geometry = split(/ /,`herbstclient monitor_rect $mon`);
    open ($dzen{$mon}, "| dzen2 -e ''\\
                          -w $geometry[2]\\
                          -x $geometry[0]\\
                          -y $geometry[1]\\
                          -fn '$font'\\
                          -h $height\\
                          -ta l\\
                          -bg '#000000'\\
                          -fg '#efefef'");
    autoflush {$dzen{$mon}} 1;
  }

  $pipe->reader();
  #Main Loop for new data
  while (<$pipe>) {
    chomp $_;
    if ($_ =~ /^date/) {
      $date_dzen_store = date_for_dzen($_);
    } elsif ($_ =~ /tag/) {
      for (my $mon = 0 ; $mon < $num_monitors ; $mon++) {
        $tags_dzen_store{$mon} = update_tag($_, $mon);
      }
    } elsif ($_ =~ /Battery/) {
      $acpi_dzen_store = $_;
      $acpi_dzen_store =~ s/Battery 0: /                /;
    } 

    for (my $mon = 0 ; $mon < $num_monitors ; $mon++) {
      print {$dzen{$mon}} $tags_dzen_store{$mon} . $acpi_dzen_store . $date_dzen_store;
      print {$dzen{$mon}} "\n";
    }
  }
}