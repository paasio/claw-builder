# CLAW Builder

CLAW is short for Cloud Awesome.  The Builder component is an implementation
that combines elements from Cloud Foundry's BOSH system, Heroku's Vulcan build
server, and Homebrew's DSL for describing packages.

Its goal is to create a distributed system for building packages in the cloud,
with manifests created and managed by a simple Ruby DSL.

The project was concieved to allow building packages for running Cloud Foundry
from within a Cloud Foundry instance. Although this does expect having a NATS
instance the application can connect to.

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
codebase within the `server` directory as a Node.JS application.

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
