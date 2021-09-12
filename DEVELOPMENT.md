# INSTALL DEPENDENCIES

    cpanm --installdeps --with-develop .        # module dependencies
    cpanm Test::JSON::Schema::Acceptance        # to test t/acceptance.t
    cpanm LWP::UserAgent                        # for now, need for some tests in t/acceptance.t
    cpanm Dist::Zilla                           # to build and upload module to cpan
    dzil authordeps --missing | cpanm           # to install dzil dependencies
    cpanm Pod::Weaver::Section::Contributors    # to automatically maintain the list of contributors
    apt-get install spell                       # for spell check

# SETUP

    dzil setup

# RUN TESTS

    prove -l t
    dzil test

# BUILD

    dzil build

# RELEASE/UPLOAD TO CPAN

    # update Changes
    # update version in JSONSchema::Validator
    dzil release
