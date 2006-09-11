# $Id: Base.pm 579 2006-01-09 21:17:54Z guillomovitch $
package Youri::Check::Report::File::Format;

=head1 NAME

Youri::Check::Report::File::Format - Abstract file format support

=head1 DESCRIPTION

This abstract class defines the format support interface for
L<Youri::Check::Report::File>.

=cut

use warnings;
use strict;
use IO::Handle;
use Carp;

sub new {
    my $class = shift;
    croak "Abstract class" if $class eq __PACKAGE__;

    my %options = (
        id      => '',
        test    => 0,
        verbose => 0,
        @_
    );

    my $self = bless {
        _id         => $options{id},
        _test       => $options{test},
        _verbose    => $options{verbose},
    }, $class;

    $self->_init(%options);

    return $self;
}

sub _init {
    # do nothing
}

=head2 get_id()

Returns format handler identity.

=cut

sub get_id {
    my ($self) = @_;
    croak "Not a class method" unless ref $self;

    return $self->{_id};
}

sub open_output {
    my ($self, $dir, $name) = @_;

    if ($self->{_test}) {
        $self->{_out} = \*STDOUT;
    } else {
        my $extension = $self->extension();
        my $file = "$dir/$name.$extension";
        my $dirname = dirname($file);
        mkpath($dirname) unless -d $dirname;
        open($self->{_out}, '>', $file) or croak "Can't open file $file: $!";
    }
}

sub close_output {
    my ($self) = @_;

    close($self->{_out}) unless $self->{_test};
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002-2006, YOURI project

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
