# CLAW Builder

CLAW is short for Cloud Awesome.  The Builder component is an implementation
that combines elements from Cloud Foundry's BOSH system, Heroku's Vulcan build
server, and Homebrew's DSL for describing packages.

Its goal is to create a distributed system for building packages in the cloud,
with manifests created and managed by a simple Ruby DSL.

The project was concieved to allow building packages for running Cloud Foundry
from within a Cloud Foundry instance. Although this does expect having a NATS
instance the application can connect to.

## Installation

The server is comprised of two components: the frontend server process, and the
backend workers that perform the actual builds.  The workers receive build jobs
over NATS and stream output back to the server, which then allows different
clients to subscribe to the output.

The server currently has a few expections:

* Currently, it is still hard-coded to utilize localhost.
* The server is hardcoded to port 8080
* The worker is hardcoded to port 8081
* It requires NATS to be up on localhost, no authentication

So it kind of expects to be localized.

To setup the server locally, do the following:

    $ cd server
    $ npm install

    In one terminal:
    $ node server.js

    In another terminal:
    $ S3_KEY="key" S3_SECRET="secret" S3_BUCKET="my-packages" node worker.js

It currently expects to be uploading direct to Amazon S3.  A future optional will
allow overriding the endpoint so it can uplaod to a vblob server, or something
else that emulates the S3 API.

Now you are ready to run some builds.

## Usage

    $ claw-builder help
    Tasks:
      claw-builder build FORMULA  # Build a package using the FORMULA file given. 
      claw-builder help [TASK]    # Describe available tasks or one specific task

    $ claw-builder help build
    Usage:
      claw-builder build FORMULA

    Build a package using the FORMULA file given.

## Examples

### Create a Build Server

This process still needs to be documented.  You essentially need to deploy the
codebase within the `server` directory as a Node.js application.

### Sample Formula

    class Memcached < PackageFormula
      name 'memcached'
      version '1.4.13+'

      source 'http://memcached.googlecode.com/files/memcached-1.4.13.tar.gz',
              :md5 => '6d18c6d25da945442fcc1187b3b63b7f'

      build do
        %Q{
          tar xzvf memcached-1.4.13.tar.gz
          cd memcached-1.4.13
          ./configure --prefix=${CLAW_PACKAGE_DIRECTORY}
          make
          make install
        }
      end
    end

### Build

    $ claw-builder build memcached.rb
    >> Uploading build manifest
    >> Tailing build...
    [snip]
    Generating checksums...
    Uploading to S3...
    >> Build complete
       Build available from http://my-packages.s3.amazonaws.com/mongodb/memcached-1.4.13+1-x86_64.tar.gz
       Checksums:
             MD5: e66fb97df7cdbde18551351726a502d8
            SHA1: 5e2ea935640ee1dac9a04884737e8f168d60d361
          SHA256: f433d2935c7b22cffccef39586617ca6691ea06df7d1ee6b2cb20c364bff6429

## Formulas

To give an example of a more fully featured formula that demonstates various
capabilities:

    class Php5 < PackageFormula
      name 'php5'
      version '5.3.10+1'

      source 'http://path/to/file.tar.gz',
             :name => 'name.tar.gz', # name overrides the working filename
             :md5 => 'sdfdsfdsfds',  # can validate md5, sha1, or sha256
             :arch => 'x86_64'       # only gets the package if worker matches the arch
                                     #  arch can be x86_64 or i386
                                     #  this is mainly useful if downloading
                                     #  precompiled binaries and repacking them

      noarch true  # normally, will package as name-version-arch.tar.gz
                   # this optional will change it to name-version-all.tar.gz
                   # it is intended if the packaging is arch-independent

      depends 'apache2', :version => '2.2.4' # TODO
      depends 'mysqlclient' # TODO, gets latest
      # depends will automatically create a "PACKAGE_PATH" var in the build script

      include_file 'php.ini'  # TODO, places in working directory

      build do
        %Q{
          echo "Extracting php5..."
          tar xzf php-5.3.10.tar.gz

          echo "Building php5..."
          cd php-5.3.10
          ./configure \
            --prefix=${APACHE2_PATH} \
            --with-apxs2=${APACHE2_PATH}/bin/apxs \
            --with-config-file-path=../php.ini \
            --with-mysql=${MYSQLCLIENT_PATH}

          # redirecting stdout to /dev/null as the output becomes too large for nats
          make
          make install

          # php installs the shared object in the apache module dir, so we need to
          # copy it back to the php package dir
          mkdir -p ${CLAW_PACKAGE_DIRECTORY}/modules
          cp ${APACHE2_PATH}/modules/libphp5.so ${CLAW_PACKAGE_DIRECTORY}/modules
        }
      end
    end
