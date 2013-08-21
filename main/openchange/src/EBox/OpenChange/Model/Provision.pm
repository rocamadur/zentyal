# Copyright (C) 2013 Zentyal S. L.
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

package EBox::OpenChange::Model::Provision;

use base 'EBox::Model::DataForm';

use EBox::Gettext;
use EBox::Types::Text;
use EBox::Types::MultiStateAction;
use EBox::Types::Action;
use EBox::Samba::User;

use Error qw( :try );

# Method: new
#
#   Constructor, instantiate new model
#
sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    bless ($self, $class);

    return $self;
}

# Method: _table
#
#   Returns model description
#
sub _table
{
    my ($self) = @_;

    my $tableDesc = [
        new EBox::Types::Text(
            fieldName => 'firstorganization',
            printableName => __('First Organization'),
            defaultValue => 'First Organization',
            editable => sub { $self->parentModule->isEnabled() and
                              not $self->parentModule->isProvisioned() }),
        new EBox::Types::Text(
            fieldName => 'firstorganizationunit',
            printableName => __('First Organization Unit'),
            defaultValue => 'First Organization Unit',
            editable => sub { $self->parentModule->isEnabled() and
                              not $self->parentModule->isProvisioned() }),
        new EBox::Types::Boolean(
            fieldName => 'enableUsers',
            printableName => __('Enable all users after provision'),
            defaultValue => 1,
            editable => sub { $self->parentModule->isEnabled() and
                              not $self->parentModule->isProvisioned() }),
    ];

    my $customActions = [
        new EBox::Types::MultiStateAction(
            acquirer => \&_acquireProvisioned,
            model => $self,
            states => {
                provisioned => {
                    name => 'deprovision',
                    printableValue => __('Deprovision'),
                    handler => \&_doDeprovision,
                    message => __('Database deprovisioned'),
                    enabled => sub { $self->parentModule->isEnabled() },
                },
                notProvisioned => {
                    name => 'provision',
                    printableValue => __('Provision'),
                    handler => \&_doProvision,
                    message => __('Database provisioned'),
                    enabled => sub { $self->parentModule->isEnabled() },
                },
            }
        ),
    ];


    my $dataForm = {
        tableName          => 'Provision',
        printableTableName => __('Provision'),
        pageTitle          => __('OpenChange Server Provision'),
        modelDomain        => 'OpenChange',
        #defaultActions     => [ 'editField' ],
        customActions      => $customActions,
        tableDescription   => $tableDesc,
        # FIXME help               => __(''),
    };

    return $dataForm;
}

# Method: precondition
#
#   Check samba is configured and provisioned
#
sub precondition
{
    my ($self) = @_;

    my $samba = EBox::Global->modInstance('samba');
    unless ($samba->configured()) {
        $self->{preconditionFail} = 'notConfigured';
        return undef;
    }
    unless ($samba->isProvisioned()) {
        $self->{preconditionFail} = 'notProvisioned';
        return undef;
    }
    unless ($self->parentModule->isEnabled()) {
        $self->{preconditionFail} = 'notEnabled';
        return undef;
    }

    return 1;
}

# Method: preconditionFailMsg
#
#   Show the precondition failure message
#
sub preconditionFailMsg
{
    my ($self) = @_;

    if ($self->{preconditionFail} eq 'notConfigured') {
        my $samba = EBox::Global->modInstance('samba');
        return __x('You must enable the {x} module in the module ' .
                  'status section before provisioning {y} module database.',
                  x => $samba->printableName(),
                  y => $self->parentModule->printableName());
    }
    if ($self->{preconditionFail} eq 'notProvisioned') {
        my $samba = EBox::Global->modInstance('samba');
        return __x('You must provision the {x} module database before ' .
                  'provisioning the {y} module database.',
                  x => $samba->printableName(),
                  y => $self->parentModule->printableName());
    }
    if ($self->{preconditionFail} eq 'notEnabled') {
        return __x('You must enable the {x} module before provision the ' .
                   'database', x => $self->parentModule->printableName());
    }
}

sub _acquireProvisioned
{
    my ($self, $id) = @_;

    my $provisioned = $self->parentModule->isProvisioned();
    return ($provisioned) ? 'provisioned' : 'notProvisioned';
}

sub _doProvision
{
    my ($self, $action, $id, %params) = @_;

    my $firstOrganization = $params{firstorganization};
    my $firstOrganizationUnit = $params{firstorganizationunit};
    my $enableUsers = $params{enableUsers};

    $self->setValue('firstorganization', $firstOrganization);
    $self->setValue('firstorganizationunit', $firstOrganizationUnit);
    $self->setValue('enableUsers', $enableUsers);

    try {
        my $cmd = '/opt/samba4/sbin/openchange_provision ' .
                  "--firstorg='$firstOrganization' " .
                  "--firstou='$firstOrganizationUnit' ";
        my $output = EBox::Sudo::root($cmd);
        EBox::debug(join('', @{$output}));

        $cmd = '/opt/samba4/sbin/openchange_provision --openchangedb';
        $output = EBox::Sudo::root($cmd);
        EBox::debug(join('', @{$output}));

        $self->parentModule->setProvisioned(1);
        $self->setMessage($action->message(), 'note');
    } otherwise {
        my ($error) = @_;

        throw EBox::Exceptions::External("Error provisioninig: $error");
        $self->parentModule->setProvisioned(0);
    } finally {
        $self->global->modChange('samba');
        $self->global->modChange('openchange');
    };

    if ($enableUsers) {
        my $usersModule = EBox::Global->modInstance('users');
        my $users = $usersModule->users();
        foreach my $ldapUser (@{$users}) {
            try {
                my $samAccountName = $ldapUser->get('uid');
                next unless defined $samAccountName;

                my $ldbUser = new EBox::Samba::User(
                        samAccountName => $samAccountName);
                next unless $ldbUser->exists();

                my $critical = $ldbUser->get('isCriticalSystemObject');
                next if (defined $critical and $critical eq 'TRUE');

                # Skip enabled users
                my $ac = $ldbUser->get('msExchUserAccountControl');
                next if (defined $ac and $ac == 0);

                my $cmd = "/opt/samba4/sbin/openchange_newuser ";
                $cmd .= " --create " if (not defined $ac);
                $cmd .= " --enable '$samAccountName' ";
                my $output = EBox::Sudo::root($cmd);
                EBox::debug(join('', @{$output}));
            } otherwise {
                my ($error) = @_;
                # Try next user
            };
        }
    }
}

sub _doDeprovision
{
    my ($self, $action, $id, %params) = @_;

    try {
        my $cmd = '/opt/samba4/sbin/openchange_provision ' .
                  '--deprovision';
        my $output = EBox::Sudo::root($cmd);
        EBox::debug(join('', @{$output}));

        $cmd = 'rm -rf /opt/samba4/private/openchange.ldb';
        $output = EBox::Sudo::root($cmd);
        EBox::debug("openchange.ldb removed");

        $self->parentModule->setProvisioned(1);
        $self->setMessage($action->message(), 'note');

        # TODO Drop postgresql database tables
    } otherwise {
        my ($error) = @_;

        throw EBox::Exceptions::External("Error deprovisioninig: $error");
        $self->parentModule->setProvisioned(1);
    } finally {
        $self->global->modChange('samba');
        $self->global->modChange('openchange');
    };
}

1;