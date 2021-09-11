# INSTALL DEPENDENCIES

    cpanm --installdeps --with-develop .        # module dependencies
    cpanm Test::JSON::Schema::Acceptance        # to test t/acceptance.t
    cpanm LWP::UserAgent                        # for now, need for some tests in t/acceptance.t
    cpanm Dist::Zilla                           # for build and upload module to cpan
    dzil authordeps --missing | cpanm           # to install dzil dependencies
    cpanm Pod::Weaver::Section::Contributors    # for contributors in README

# SETUP

    dzil setup

# RUN TESTS

    prove -l t
    dzil test

# BUILD

    dzil
