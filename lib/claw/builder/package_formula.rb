class PackageFormula
  class << self
    def name(val=nil)
      @spec[:name] = val if val
      @spec[:name]
    end

    def version(val=nil)
      @spec[:version] = val if val
      @spec[:version]
    end

    def source(url, opts={})
      @spec[:sources] << opts.merge(:url => url)
      @spec[:sources]
    end

    def depends(package, opts={})
      @spec[:dependencies] << opts.merge(:name => package)
      @spec[:dependencies]
    end

    def include_file(name, opts={})
      @spec[:included_files] << opts.merge(
        :name => File.basename(name),
        :path => File.expand_path(name)
      )
      @spec[:included_files]
    end

    def noarch(val=true)
      @spec[:noarch] = val
      @spec[:noarch]
    end

    def build
      @spec[:build_script] = yield if block_given?
      @spec[:build_script]
    end

    def to_spec
      @spec
    end

    def inherited(child)
      if self == PackageFormula
        child.init_package_spec
      else
        child.copy_package_spec(@spec)
      end
    end

    protected

    def init_package_spec
      @spec = {
        :version => '0.0.1',
        :sources => [],
        :dependencies => [],
        :included_files => [],
        :noarch => false
      }
    end

    def copy_package_spec(spec)
      @spec = spec.dup
    end
  end
end
