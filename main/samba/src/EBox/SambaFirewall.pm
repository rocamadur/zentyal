# Copyright (C) 2008-2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

package EBox::SambaFirewall;

use base 'EBox::FirewallHelper';

use EBox::Objects;
use EBox::Global;
use EBox::Config;
use EBox::Firewall;
use EBox::Gettext;

use constant SAMBAPORTS => qw(137 138 139 445);

sub new
{
    my $class = shift;
    my %opts = @_;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return $self;
}

sub output
{
    my ($self) = @_;
    my @rules = ();

    my $samba = EBox::Global->modInstance('samba');
    my @ifaces = @{ $samba->sambaInterfaces() };
    foreach my $ifc (@ifaces) {
        # dont firewall loopback interface
        next if $ifc eq 'lo';

        my $output = $self->_outputIface($ifc);

        foreach my $port (SAMBAPORTS) {
            my $r = "-m state --state NEW $output  ".
                "-p tcp --sport $port -j oaccept";
            push(@rules, $r);
            $r = "-m state --state NEW $output ".
                "-p udp --sport $port -j oaccept";
            push(@rules, $r);
            $r = "-m state --state NEW $output  ".
                "-p tcp --dport $port -j oaccept";
            push(@rules, $r);
            $r = "-m state --state NEW $output  ".
                "-p udp --dport $port -j oaccept";
            push(@rules, $r);
        }
    }

    return \@rules;
}

1;
