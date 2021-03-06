use strict;
use warnings;

use Test::More 0.88;
use Test::Fatal;

my $default_description = 'Clearly nothing that you care about';
{
    # Our base class has an attribute that's nothing special, and another one
    # that most of these tests will ignore.
    package Account;
    use Moose;
    use MooseX::LazyRequire;

    has password => (
        is  => 'rw',
        isa => 'Str',
    );
    has description => (
        is      => 'rw',
        isa     => 'Str',
        lazy    => 1,
        default => sub { $default_description }
    );

    # The extended class wants you to specify a password, eventually.
    package AccountExt;

    use Moose;
    extends 'Account';
    use MooseX::LazyRequire;

    has '+password' => (
        is            => 'ro',
        lazy_required => 1,
    );

    # A further subclass insists that you supply the password immediately.
    package AccountExt::Harsh;

    use Moose;
    extends 'AccountExt';
    use MooseX::LazyRequire;

    has '+password' => (
        is            => 'ro',
        lazy_required => 0,
        required      => 1,
    );

    # Another subclass makes the attribute lazy.
    package AccountExt::Lazy;

    use Moose;
    extends 'AccountExt';
    use MooseX::LazyRequire;

    $AccountExt::Lazy::default_password = 'password';
    has '+password' => (
        lazy_required => 0,
        lazy          => 1,
        default       => sub { $AccountExt::Lazy::default_password },
    );

    # Another subclass will supply one for you if you don't specify one.
    package AccountExt::Lax::Default;

    use Moose;
    extends 'AccountExt';
    use MooseX::LazyRequire;

    has '+password' => (
        lazy_required => 0,
        default       => sub { 'hunter2' },
    );

    # But if you don't override the default, you're SOL.
    package AccountExt::Lax::Woo;

    use Moose;
    extends 'AccountExt';
    use MooseX::LazyRequire;

    has '+password' => (lazy_required => 0);

    # If you don't mention lazy_required *at all* when overriding an
    # attribute, that's fine.
    package Account::Logged;

    use Moose;
    extends 'Account';
    use MooseX::LazyRequire;

    has 'description_history' => (
        is      => 'rw',
        isa     => 'ArrayRef',
        default => sub { [] },
    );
    has '+description' => (
        trigger => sub {
            my ($self, $new_value, $old_value) = @_;
            push @{ $self->description_history }, $new_value;
        }
    );
}

# In the extension class, asking about a password generates an exception,
# when you ask about it.
my $account_ext = AccountExt->new;
my $exception_ext_password = exception { $account_ext->password };
isnt($exception_ext_password, undef,
    'works on inherited attributes: exception')
&& like(
    $exception_ext_password,
    qr/Attribute 'password' must be provided before calling reader/,
    'works on inherited attributes: mentions password by name'
);
my $attribute_ext = $account_ext->meta->find_attribute_by_name('password');
ok($attribute_ext->lazy_required,
    'The inherited attribute is now lazy-required');

# These subclasses turn lazy_required *off* again, sometimes adding in elements
# that lazy_required provides.
# The lax subclass is happy to provide you with a default password.
my $account_ext_lax_default = AccountExt::Lax::Default->new;
is($account_ext_lax_default->password,
    'hunter2',
    'We can override LazyRequired *off* as well');

# The harsh subclass generates an exception as soon as you don't provide a
# password.
my $exception_harsh_constructor = exception { AccountExt::Harsh->new };
isnt($exception_harsh_constructor, undef,
    'Cannot create a harsh object without a password');

# The lazy subclass will use a lazily-generated value.
my $lazy = AccountExt::Lazy->new;
{
    local $AccountExt::Lazy::default_password = 'qwerty';
    is($lazy->password, 'qwerty',
        'The lazy object resolves its default value as late as possible'
    );
}

# The woo subclass really wants to be the base subclass, but can't, because
# a default option got in the way in the inheritance hierarchy.
my $exception_ext_woo_password = exception { AccountExt::Lax::Woo->new };
like(
    $exception_ext_woo_password,
    qr/Attribute .+ password .+ \Qdoes not pass the type constraint\E/x,
    'Falling back to undef as a last resort violates type constraints'
);

# We don't mess with attributes in classes that use MooseX::LazyRequire but
# don't set lazy_require explicitly, not even when subclassing attributes.
my $logged = Account::Logged->new;
is($logged->description, $default_description,
    'When lazy_required is omitted entirely, the default etc. is unaffected');
$logged->description('Now for something else');
is($logged->description_history->[0], 'Now for something else',
    'The trigger fired, though, so we *did* change that attribute');

done_testing;
