#!/usr/bin/env bash
# Installs the Perl test harness from ci/cpan.lock, then proves the
# installed closure is exactly what the lock names, so an unpinned
# transitive dependency fails the build instead of drifting quietly.
set -euo pipefail

LOCK="${1:-/ci/cpan.lock}"

# already in dependency order
mapfile -t PINS < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LOCK")
test "${#PINS[@]}" -gt 0

cpanm --notest --no-man-pages "${PINS[@]}"
rm -rf /root/.cpanm

perl -MTest::Nginx::Socket::Lua -e1

LOCK="$LOCK" perl -MExtUtils::Installed -Mversion -e '
    my %want;
    open my $fh, "<", $ENV{LOCK} or die "cannot read $ENV{LOCK}: $!";
    while (<$fh>) {
        s/#.*//;
        next unless /\S/;
        chomp;
        my ($mod, $ver) = split /@/;
        $want{$mod} = $ver;
    }

    my @bad;
    my $inst = ExtUtils::Installed->new;
    for my $mod ($inst->modules) {
        next if $mod eq "Perl";           # core, pinned by the base image
        my $got = eval { $inst->version($mod) } // "undef";
        if (!exists $want{$mod}) {
            push @bad, "$mod=$got is installed but not pinned";
            next;
        }
        push @bad, "$mod=$got is installed, lock says $want{$mod}"
            unless eval { version->parse($got) == version->parse($want{$mod}) };
        delete $want{$mod};
    }
    push @bad, "$_ is pinned but was not installed" for sort keys %want;

    die "CPAN closure does not match the lock:\n  " . join("\n  ", @bad) . "\n"
        if @bad;
'

printf 'CPAN closure matches %s (%d distributions)\n' "$LOCK" "${#PINS[@]}"
