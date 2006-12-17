# $Id$
package Youri::Check::Test::Rpmcheck;

=head1 NAME

Youri::Check::Test::Rpmcheck - Check package dependencies with rpmcheck

=head1 DESCRIPTION

This plugins checks package dependencies with rpmcheck, and reports output.

=cut

use warnings;
use strict;
use Carp;
 use File::Temp qw/tempdir/;
use base 'Youri::Check::Test';

my $descriptor = Youri::Check::Descriptor::Row->new(
    cells => [
        Youri::Check::Descriptor::Cell->new(
            name        => 'source package',
            description => 'source package',
            mergeable   => 1,
            value       => 'source_package',
            type        => 'string',
        ),
        Youri::Check::Descriptor::Cell->new(
            name        => 'maintainer',
            description => 'maintainer',
            mergeable   => 1,
            value       => 'maintainer',
            type        => 'email',
        ),
        Youri::Check::Descriptor::Cell->new(
            name        => 'architecture',
            description => 'architecture',
            mergeable   => 0,
            value       => 'arch',
            type        => 'string',
        ),
        Youri::Check::Descriptor::Cell->new(
            name        => 'package',
            description => 'package',
            mergeable   => 0,
            value       => 'package',
            type        => 'string',
        ),
        Youri::Check::Descriptor::Cell->new(
            name        => 'reason',
            description => 'reason',
            mergeable   => 0,
            value       => 'reason',
            type        => 'string',
        )
    ]
);

sub get_descriptor {
    return $descriptor;
}

=head2 new(%args)

Creates and returns a new Youri::Check::Test::Rpmcheck object.

Specific parameters:

=over

=item path $path

Path to the rpmcheck executable (default: /usr/bin/rpmcheck)

=back

=cut


sub _init {
    my $self    = shift;
    my %options = (
        path   => '/usr/bin/rpmcheck',
        @_
    );

    $self->{_path}   = $options{path};
}

sub prepare {
    my ($self, @medias) = @_;
    croak "Not a class method" unless ref $self;

    $self->{_hdlists} = tempdir(CLEANUP => 1);

    foreach my $media (@medias) {
        # uncompress hdlist, as rpmcheck does not handle them
        my $media_id = $media->get_id();
        my $hdlist = $media->get_hdlist();
        system("zcat $hdlist 2>/dev/null > $self->{_hdlists}/$media_id");
    }
}


sub run {
    my ($self, $media, $resultset) = @_;
    croak "Not a class method" unless ref $self;

    # index packages first
    my $packages;
    my $index = sub {
        my ($package) = @_;

        $packages->{$package->get_name()} = $package;
    };
    $media->traverse_headers($index);

    # then run rpmcheck
    my $command = "$self->{_path} -explain -failures";
    my $allowed_ids = $media->get_option($self->{_id}, 'allowed');
    my $id = $media->get_id();
    foreach my $allowed_id (@{$allowed_ids}) {
        if ($allowed_id eq $id) {
            carp "incorrect value in $self->{_id} allowed option for media $id: media self-reference";
            next;
        }
        $command .= " -base $self->{_hdlists}/$allowed_id";
    }
    $command .= " <$self->{_hdlists}/$id 2>/dev/null";
    open(my $input, '-|', $command) or croak "Can't run $command: $!";
    my $package_pattern = qr/^
        (\S+) \s
        \(= \s \S+\):
        \s FAILED
        $/x;
    my $reason_pattern  = qr/^
        \s+
        \S+ \s
        \([^)]+\) \s
        (depends \s on|conflicts \s with) \s
        (\S+ (?:\s \([^)]+\))?) \s
        \{([^}]+)\}
        (?: \s on \s file \s (\S+))?
        $/x;
    PACKAGE: while (my $line = <$input>) {
        if ($line !~ $package_pattern) {
            warn "$line doesn't conform to expected format";
            next PACKAGE;
        }
        my $name = $1;
        my $package = $packages->{$name};
        my $arch = $package->get_arch();
        # skip next line
        $line = <$input>;
        # read first reason
        $line = <$input>;
        if ($line !~ $reason_pattern) {
            warn "$line doesn't conform to expected format";
            next PACKAGE;
        }
        my $problem = $1;
        my $dependency = $2;
        my $status = $3;
        my $file = $4;

        # find the exact problem reason
        my $reason;
        if ($problem eq 'depends on') {
            if ($status eq 'NOT AVAILABLE') {
                $reason = "$dependency is missing";
            } else {
                $reason = "$dependency is not installable";
                # exhaust indirect reasons
                REASON: while ($line 
                    && $status ne 'NOT AVAILABLE'
                    && $problem ne 'conflicts with'
                ) {
                    $line = <$input>;
                    if ($line !~ $reason_pattern) {
                        warn "$line doesn't conform to expected format";
                        next REASON;
                    }
                    $problem = $1;
                    $status = $3;
                }
            }
        } else {
            $reason = $file ?
                "implicit conflict with $dependency on file $file" :
                "explicit conflict with $dependency";
        }

        $resultset->add_result(
            $self->{_id}, $media, $package, { 
            arch    => $arch,
            package => $name,
            reason  => $reason
        });
    }
    close $input;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002-2006, YOURI project

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
