#!/usr/bin/env bash
# Runs inside firefart/requesttracker:latest (as root), with the repo
# checkout bind-mounted at /workspace. See .github/workflows/publish.yml.
#
# RTx() in Makefile.PL needs a real, fully-installed RT to configure (it
# require()s RT.pm and reads $RT::LocalLibPath etc.), which is why this
# can't just run on a stock GitHub-hosted runner -- there's no live RT
# there. This container is the smallest thing that satisfies that.
set -euo pipefail

: "${RELEASE_TAG:?RELEASE_TAG must be set}"
: "${PAUSE_USERNAME:?PAUSE_USERNAME must be set}"
: "${PAUSE_PASSWORD:?PAUSE_PASSWORD must be set}"

cd /workspace

module_version=$(perl -Ilib -MRT::Extension::AwayMode -e 'print $RT::Extension::AwayMode::VERSION')
tag_version="${RELEASE_TAG#v}"

if [ "$module_version" != "$tag_version" ]; then
    echo "::error::Release tag '$RELEASE_TAG' (version '$tag_version') does not match \$VERSION in lib/RT/Extension/AwayMode.pm ('$module_version')"
    exit 1
fi

echo "Publishing RT-Extension-AwayMode $module_version"

# Module::Install's Makefile.PL only writes META.yml/MANIFEST/inc/ in
# "admin" mode, which requires the real (non-vendored) Module::Install and
# Module::Install::RTx to be installed -- see CLAUDE.md's "Releasing to
# CPAN" section.
cpanm --notest Module::Install Module::Install::RTx CPAN::Uploader

perl Makefile.PL

# RTx's own readme_from renders POD C<...> codes without quotes, which
# doesn't match this repo's plain pod2text convention; regenerate README
# the same way CLAUDE.md documents for local releases.
pod2text lib/RT/Extension/AwayMode.pm README

make manifest
make dist

perl -MCPAN::Meta -e '
    my $meta = CPAN::Meta->load_file("META.yml");
    my $v = CPAN::Meta::Validator->new($meta->as_struct);
    die join("\n", $v->errors), "\n" unless $v->is_valid;
    print "META.yml is valid\n";
'

prove -lr t/

tarball="RT-Extension-AwayMode-$module_version.tar.gz"
if [ ! -f "$tarball" ]; then
    echo "::error::Expected tarball $tarball was not produced by 'make dist'"
    exit 1
fi

umask 077
trap 'rm -f "$HOME/.pause"' EXIT
cat > "$HOME/.pause" <<EOF
user $PAUSE_USERNAME
password $PAUSE_PASSWORD
EOF

cpan-upload "$tarball"

echo "Uploaded $tarball to PAUSE"
