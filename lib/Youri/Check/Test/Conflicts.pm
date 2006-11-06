# $Id$
package Youri::Check::Test::Conflicts;

=head1 NAME

Youri::Check::Test::Conflicts - Check file conflicts

=head1 DESCRIPTION

This plugin checks packages files, and report conflict and duplications.

=cut

use warnings;
use strict;
use Carp;
use constant;
use Youri::Package;
use base 'Youri::Check::Test';

use constant PACKAGE   => 0;
use constant DIRECTORY => 1;
use constant MD5SUM    => 2;

my $compatibility = {
    x86_64  => 'i586',
    i586    => 'x86_64',
    sparc64 => 'sparc',
    sparc   => 'sparc64',
    ppc64   => 'ppc',
    ppc     => 'ppc64'
};

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
            name        => 'error',
            description => 'error',
            mergeable   => 0,
            value       => 'error',
            type        => 'string',
        ),
        Youri::Check::Descriptor::Cell->new(
            name        => 'level',
            description => 'level',
            mergeable   => 0,
            value       => 'level',
            type        => 'string',
        ),
    ]
);

sub get_descriptor {
    return $descriptor;
}

=head2 new(%args)

Creates and returns a new Youri::Check::Test::Conflicts object.

No specific parameters.

=cut

sub prepare {
    my ($self, @medias) = @_;
    croak "Not a class method" unless ref $self;

    my $index = sub {
        my ($package) = @_;

        # index files
        foreach my $file ($package->get_files()) {
            push(
                @{$self->{_files}->{$file->get_name()}},
                [ $package, $file->is_directory(), $file->get_md5sum() ]
            );
        }
    };

    foreach my $media (@medias) {
        # don't index source media files
        next unless $media->get_type() eq 'binary';

        my $media_id = $media->get_id();
        $self->{_medias}->{$media_id} = 1;
        print STDERR "Indexing media $media_id files\n"
            if $self->{_verbose};

        $media->traverse_headers($index);
    }
}

sub run {
    my ($self, $media, $result) = @_;
    croak "Not a class method" unless ref $self;

    # this is a binary media check only
    return unless $media->get_type() eq 'binary';

    my $check = sub {
        my ($package) = @_;

        return if $package->get_arch() eq 'src';

        my $arch = $package->get_arch();
        my $name = $package->get_name();

        foreach my $file ($package->get_files()) {

            my $found =
                $self->{_files}->{$file->get_name()};

            my @found = $found ? @$found : ();

            foreach my $found (@found) {
                next if $found->[PACKAGE] == $package;
                next unless compatible($found->[PACKAGE], $package);
                next if conflict($found->[PACKAGE], $package);
                next if replace($found->[PACKAGE], $package);
                if ($file->is_directory() && $found->[DIRECTORY]) {
                    $result->add_result($self->{_id}, $media, $package, {
                        arch    => $arch,
                        package => $name,
                        error   => "directory " . $file->get_name() . " duplicated with package " . $found->[PACKAGE]->get_name(),
                        level   => Youri::Check::Test::WARNING
                    }) unless $self->_directory_duplicate_exception(
                        $package,
                        $found->[PACKAGE],
                        $file
                    );
                } else {
                    if ($found->[MD5SUM] eq $file->get_md5sum()) {
                        $result->add_result($self->{_id}, $media, $package, {
                            arch    => $arch,
                            package => $name,
                            error   => "file ". $file->get_name() . " duplicated with package " . $found->[PACKAGE]->get_name(),
                            level   => Youri::Check::Test::WARNING
                        }) unless $self->_file_duplicate_exception(
                            $package,
                            $found->[PACKAGE],
                            $file
                        );
                    } else {
                        $result->add_result($self->{_id}, $media, $package, {
                            arch    => $arch,
                            package => $name,
                            error   => "non-explicit conflict on file " . $file->get_name() . " with package " . $found->[PACKAGE]->get_name(),
                            level  => Youri::Check::Test::ERROR
                        }) unless $self->_file_conflict_exception(
                            $package,
                            $found->[PACKAGE],
                            $file
                        );
                    }
                }
            }
        }
    };

    $media->traverse_headers($check);
}

# return true if $package1 is arch-compatible with $package2
sub compatible {
    my ($package1, $package2) = @_;

    my $arch1 = $package1->get_arch();
    my $arch2 = $package2->get_arch();

    return 1 if $arch1 eq $arch2;

    return 1 if $compatibility->{$arch1} && $compatibility->{$arch1} eq $arch2;

    return 0;
}

# return true if $package1 conflict with $package2
# or the other way around
sub conflict {
    my ($package1, $package2) = @_;

    my $name2 = $package2->get_name();

    foreach my $conflict ($package1->get_conflicts()) {
        return 1 if $conflict eq $name2;
    }

    my $name1 = $package1->get_name();

    foreach my $conflict ($package2->get_conflicts()) {
        return 1 if $conflict eq $name1;
    }

    return 0;
}

# return true if $package1 replace $package2
sub replace {
    my ($package1, $package2) = @_;


    my $name1 = $package1->get_name();
    my $name2 = $package2->get_name();

    return 1 if $name1 eq $name2;

    foreach my $obsolete ($package1->get_obsoletes()) {
        return 1 if $obsolete->get_name() eq $name2;
    }

    return 0;
}

sub _directory_duplicate_exception {
    return 0;
}

sub _file_duplicate_exception {
    return 0;
}

sub _file_conflict_exception {
    return 0;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002-2006, YOURI project

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
