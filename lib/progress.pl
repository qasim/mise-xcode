#!/usr/bin/perl
# Turns the output of xcodes and xcodebuild downloads into plain lines in one
# style: progress as one line every 10%, other lines as they are, and none of
# the chatter that repeats what the plugin says. Left alone, both tools draw
# progress on a single line that they redraw, and xcodebuild never names what
# it downloads and overwrites that line when it finishes.
#
#   progress.pl [--interactive] <label> [step] [plugin]
#
# Reads the tool's output on stdin. Progress prints as
# "<step><label>: 40% (335 MB of 838.9 MB)". Given a plugin name, lines also
# start with the prefix mise gives a plugin's own messages, such as
# "mise [xcode] ", for output that goes straight to the terminal instead of
# through mise.
#
# Without --interactive, the tool has no input, and this exits 75 when it
# stopped because it needs an Apple ID sign-in, so the plugin can run it again
# with --interactive. With --interactive, the tool runs under `script` attached
# to the terminal: a line that stops at a prompt, such as "Apple ID: ", is
# shown as soon as output pauses, and what the person types is shown as they
# type it.

use strict;
use warnings;
use IO::Select;

my $interactive = 0;
if (@ARGV && $ARGV[0] eq '--interactive') {
    $interactive = 1;
    shift @ARGV;
}
my $label = shift @ARGV // 'Downloading';
my $step = shift @ARGV // '';
my $plugin = shift @ARGV // '';

# mise dims "mise" in a terminal, unless NO_COLOR is set.
my $styled = -t STDOUT && !defined $ENV{NO_COLOR};
my $prefix = ($plugin eq '' ? '' : ($styled ? "\e[2mmise\e[0m" : 'mise') . " [$plugin] ") . $step;

# `script` puts the terminal in raw mode, where a newline does not return to
# the start of the line.
my $newline = $interactive ? "\r\n" : "\n";
$| = 1;

my @chatter = (
    qr/^Finding content/,
    qr/^Automatically resolved/,
    qr/^Downloaded asset to/,
    qr/Installing\.\.\.$/,
    qr/^Done\.$/,
    qr/^Downloading with urlSession/,
    qr/^Downloading with aria2/,
    qr/ has been downloaded to /,
    qr/^Beginning asset download/,
    qr/^Done downloading/,
    qr/^Install Started/,
    qr/^Install Succeeded/,
    qr/^Developer mode is now enabled/,
    qr/^Updating\.\.\.$/,
    qr/Found existing archive/,
    qr/Writing error result bundle/,
);

# Bytes in each size unit the tools print.
my %unit = (
    bytes => 1, B => 1,
    KB => 1e3, kB => 1e3, MB => 1e6, GB => 1e9, TB => 1e12,
    KiB => 1024, MiB => 1024**2, GiB => 1024**3, TiB => 1024**4,
);

my @sign_in = (
    qr/^Apple ID/,
    qr/Missing username or a password/,
    qr/[Tt]wo-factor/,
    qr/verification code/,
    qr/trusted devices/,
);

my ($previous, $last_step, $wants_sign_in) = ('', -1, 0);

sub clean {
    my ($text) = @_;
    $text =~ s/\e\[[\d;?]*[A-Za-z]//g;
    $text =~ s/\^D//g;
    $text =~ s/[\x00-\x08\x0b-\x1f]//g;
    return $text;
}

sub finish_line {
    my ($text) = @_;
    $text = clean($text);
    $text =~ s/^\s+|\s+$//g;
    return if $text eq '';

    if (!$interactive && grep { $text =~ $_ } @sign_in) {
        # xcodes shows these when it runs again attached to the terminal.
        $wants_sign_in = 1;
        return;
    }
    return if grep { $text =~ $_ } @chatter;

    my $percent;
    if ($text =~ /(\d+(?:\.\d+)?)%/) {
        $percent = $1;
    }
    elsif ($text =~ /\(([\d.]+)\s*(\w+) of ([\d.]+)\s*(\w+)(?: downloaded)?\)/
        && $unit{$2} && $unit{$4} && $3 > 0)
    {
        # xcodebuild reports some downloads only as sizes.
        $percent = 100 * ($1 * $unit{$2}) / ($3 * $unit{$4});
    }
    if (defined $percent) {
        my $step = int($percent / 10);
        return if $step <= $last_step;
        $last_step = $step;
        my $size;
        if ($text =~ /\(([^()]* of [^()]*?)(?: downloaded)?\)/) {
            $size = $1;
        }
        elsif ($text =~ m{([\d.]+[A-Za-z]+)/([\d.]+[A-Za-z]+)\(\d+%\)}) {
            $size = "$1 of $2";
        }
        print "$prefix$label: " . int($percent) . '%' . (defined $size ? " ($size)" : '') . $newline;
        return;
    }

    print "$prefix$text$newline" unless $text eq $previous;
    $previous = $text;
}

my $buffer = '';

# How much of the current, unfinished line is already on screen, because it
# was a prompt.
my $shown = 0;

sub show_unfinished_line {
    return if length($buffer) <= $shown;
    my $text = clean(substr($buffer, $shown));
    print(($shown == 0 ? $prefix : '') . $text);
    $shown = length($buffer);
}

my $select = IO::Select->new(\*STDIN);
while (1) {
    if ($interactive && !$select->can_read(0.2)) {
        # Output paused partway through a line that ends like a prompt.
        my $text = clean($buffer);
        show_unfinished_line() if $shown == 0 && $text =~ /[:?]\s*$/ && $text !~ /%/;
        next;
    }
    last unless sysread(STDIN, my $chunk, 4096);
    $buffer .= $chunk;
    while ($buffer =~ s/^([^\r\n]*)[\r\n]//) {
        my $line = $1;
        if ($shown > 0) {
            # The rest of a prompt's line is what the person typed.
            print clean(substr($line, $shown)) . $newline if length($line) >= $shown;
            $shown = 0;
        }
        else {
            finish_line($line);
        }
    }
    # Show typing as it happens once a prompt is on screen.
    show_unfinished_line() if $shown > 0;
}
finish_line($buffer) if $shown == 0;

exit($wants_sign_in ? 75 : 0);
