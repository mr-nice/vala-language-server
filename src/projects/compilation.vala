/* compilation.vala
 *
 * Copyright 2020 Princeton Ferro <princetonferro@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gee;

class Vls.Compilation : BuildTarget {
    private HashSet<string> _packages = new HashSet<string> ();
    private HashSet<string> _defines = new HashSet<string> ();

    private HashSet<string> _vapi_dirs = new HashSet<string> ();
    private HashSet<string> _gir_dirs = new HashSet<string> ();
    private HashSet<string> _metadata_dirs = new HashSet<string> ();
    private HashSet<string> _gresources_dirs = new HashSet<string> ();

    /**
     * These are files that are part of the project.
     */
    private HashMap<File, TextDocument> _project_sources = new HashMap<File, TextDocument> (Util.file_hash, Util.file_equal);

    /**
     * This is the list of initial content for project source files.
     * Used for files that do not exist ('untitled' files);
     */
    private HashMap<File, string> _sources_initial_content = new HashMap<File, string> (Util.file_hash, Util.file_equal);

    /**
     * These may not exist until right before we compile the code context.
     */
    private HashSet<File> _generated_sources = new HashSet<File> (Util.file_hash, Util.file_equal);

    /**
     * The analyses for each project source.
     */
    private HashMap<Vala.SourceFile, HashMap<Type, CodeAnalyzer>> _source_analyzers = new HashMap<Vala.SourceFile, HashMap<Type, CodeAnalyzer>> ();

    public Vala.CodeContext code_context { get; private set; default = new Vala.CodeContext (); }

    // CodeContext arguments:
    private bool _deprecated;
    private bool _experimental;
    private bool _experimental_non_null;
    private bool _abi_stability;
    private string? _target_glib;

    /**
     * The output directory.
     */
    public string directory { get; private set; }
    private Vala.Profile _profile;
    private string? _entry_point_name;
    private bool _fatal_warnings;

    /**
     * Absolute path to generated VAPI
     */
    private string? _output_vapi;

    /**
     * Absolute path to generated GIR
     */
    private string? _output_gir;

    /**
     * Absolute path to generated internal VAPI
     */
    private string? _output_internal_vapi;

    private bool _completed_first_compile;

    /**
     * The reporter for the code context
     */
    public Reporter reporter {
        get {
            assert (code_context.report is Reporter);
            return (Reporter) code_context.report;
        }
    }

    /**
     * Maps a symbol's C name to the actual symbol. The documentation engine
     * uses this to replace references to C symbols with appropriate Vala references.
     */
    public HashMap<string, Vala.Symbol> cname_to_sym { get; private set; default = new HashMap<string, Vala.Symbol> (); }

    public Compilation (string output_dir, string name, string id, int no,
                        string[] compiler, string[] args, string[] sources, string[] generated_sources,
                        string?[] target_output_files,
                        string[]? sources_content = null) throws Error {
        base (output_dir, name, id, no);
        directory = output_dir;

        // parse arguments
        var output_dir_file = File.new_for_path (output_dir);
        bool set_directory = false;
        string? flag_name, arg_value;           // --<flag_name>[=<arg_value>]

        // because we rely on --directory for determining the location of output files
        // because we rely on --basedir (if defined) for determining the location of input files
        for (int arg_i = -1; (arg_i = Util.iterate_valac_args (args, out flag_name, out arg_value, arg_i)) < args.length;) {
            if (flag_name == "directory") {
                if (arg_value == null) {
                    warning ("Compilation(%s) null --directory", id);
                    continue;
                }
                directory = Util.realpath (arg_value, output_dir);
                set_directory = true;
            }
        }

        for (int arg_i = -1; (arg_i = Util.iterate_valac_args (args, out flag_name, out arg_value, arg_i)) < args.length;) {
            if (flag_name == "pkg") {
                _packages.add (arg_value);
            } else if (flag_name == "vapidir") {
                _vapi_dirs.add (arg_value);
            } else if (flag_name == "girdir") {
                _gir_dirs.add (arg_value);
            } else if (flag_name == "metadatadir") {
                _metadata_dirs.add (arg_value);
            } else if (flag_name == "gresourcesdir") {
                _gresources_dirs.add (arg_value);
            } else if (flag_name == "define") {
                _defines.add (arg_value);
            } else if (flag_name == "enable-experimental") {
                _experimental = true;
            } else if (flag_name == "enable-experimental-non-null") {
                _experimental_non_null = true;
            } else if (flag_name == "fatal-warnings") {
                _fatal_warnings = true;
            } else if (flag_name == "profile") {
                if (arg_value == "posix")
                    _profile = Vala.Profile.POSIX;
                else if (arg_value == "gobject")
                    _profile = Vala.Profile.GOBJECT;
                else
                    throw new ProjectError.INTROSPECTION (@"Compilation($id) unsupported Vala profile `$arg_value'");
            } else if (flag_name == "abi-stability") {
                _abi_stability = true;
            } else if (flag_name == "target-glib") {
                _target_glib = arg_value;
            } else if (flag_name == "vapi" || flag_name == "gir" || flag_name == "internal-vapi") {
                if (arg_value == null) {
                    warning ("Compilation(%s) --%s is null", id, flag_name);
                    continue;
                }

                string path = Util.realpath (arg_value, directory);
                if (!set_directory)
                    warning ("Compilation(%s) no --directory given, assuming %s", id, directory);
                if (flag_name == "vapi")
                    _output_vapi = path;
                else if (flag_name == "gir")
                    _output_gir = path;
                else
                    _output_internal_vapi = path;

                output.add (File.new_for_path (path));
            } else if (flag_name == null) {
                if (arg_value == null) {
                    warning ("Compilation(%s) failed to parse argument #%d (%s)", id, arg_i, args[arg_i]);
                } else if (Util.arg_is_vala_file (arg_value)) {
                    var file_from_arg = File.new_for_path (Util.realpath (arg_value, output_dir));
                    if (output_dir_file.get_relative_path (file_from_arg) != null)
                        _generated_sources.add (file_from_arg);
                    input.add (file_from_arg);
                }
            } else if (flag_name != "directory") {
                debug ("Compilation(%s) ignoring argument #%d (%s)", id, arg_i, args[arg_i]);
            }
        }

        for (int i = 0; i < sources.length; i++) {
            unowned string source = sources[i];
            unowned string? content = sources_content != null ? sources_content[i] : null;

            string? uri_scheme = Uri.parse_scheme (source);
            if (uri_scheme != null && uri_scheme.down () != "c") {
                var file = File.new_for_uri (source);
                input.add (file);
                if (content != null)
                    _sources_initial_content[file] = content;
            } else {
                input.add (File.new_for_path (Util.realpath (source, output_dir)));
            }
        }

        foreach (string generated_source in generated_sources) {
            var generated_source_file = File.new_for_path (Util.realpath (generated_source, output_dir));
            _generated_sources.add (generated_source_file);
            input.add (generated_source_file);
        }

        // add the rest of these target output files
        foreach (string? output_file in target_output_files) {
            if (output_file != null) {
                if (output.add (File.new_for_commandline_arg_and_cwd (output_file, output_dir)))
                    debug ("Compilation(%s): also outputs %s", id, output_file);
            }
        }

        // finally, add these very important packages
        if (_profile == Vala.Profile.POSIX) {
            _packages.add ("posix");
        } else {
            _packages.add ("glib-2.0");
            _packages.add ("gobject-2.0");
            if (_profile != Vala.Profile.GOBJECT)
                warning ("Compilation(%s) no --profile argument given, assuming GOBJECT", id);
        }
    }

    private void configure (Cancellable? cancellable = null) throws Error {
        // 1. recreate code context
        code_context = new Vala.CodeContext () {
            deprecated = _deprecated,
            experimental = _experimental,
            experimental_non_null = _experimental_non_null,
            abi_stability = _abi_stability,
            directory = directory,
            vapi_directories = _vapi_dirs.to_array (),
            gir_directories = _gir_dirs.to_array (),
            metadata_directories = _metadata_dirs.to_array (),
            keep_going = true,
            // report = new Reporter (_fatal_warnings),
            entry_point_name = _entry_point_name,
            gresources_directories = _gresources_dirs.to_array ()
        };

#if VALA_0_50
        code_context.set_target_profile (_profile, false);
#else
        code_context.profile = _profile;
        switch (_profile) {
            case Vala.Profile.POSIX:
                code_context.add_define ("POSIX");
                break;
            case Vala.Profile.GOBJECT:
                code_context.add_define ("GOBJECT");
                break;
        }
#endif

        // Vala compiler bug requires us to initialize things this way instead of
        // the alternative above
        code_context.report = new Reporter (_fatal_warnings);

        // set target GLib version if specified
        if (_target_glib != null)
            code_context.set_target_glib_version (_target_glib);
        Vala.CodeContext.push (code_context);

        foreach (string define in _defines)
            code_context.add_define (define);

        if (_project_sources.is_empty) {
            debug ("Compilation(%s): will load input sources for the first time", id);
            if (input.is_empty)
                warning ("Compilation(%s): no input sources to load!", id);
            foreach (File file in input) {
                if (!dependencies.has_key (file)) {
                    try {
                        _project_sources[file] = new TextDocument (code_context, file, _sources_initial_content[file], true);
                    } catch (Error e) {
                        warning ("Compilation(%s): %s", id, e.message);
                        Vala.CodeContext.pop ();
                        throw e;    // rethrow
                    }
                } else
                    _generated_sources.add (file);

                cancellable.set_error_if_cancelled ();
            }
        }

        foreach (TextDocument doc in _project_sources.values) {
            doc.context = code_context;
            code_context.add_source_file (doc);
            // clear all using directives (to avoid "T ambiguous with T" errors)
            doc.current_using_directives.clear ();
            // add default using directives for the profile
            if (_profile == Vala.Profile.POSIX) {
                // import the Posix namespace by default (namespace of backend-specific standard library)
                var ns_ref = new Vala.UsingDirective (new Vala.UnresolvedSymbol (null, "Posix", null));
                doc.add_using_directive (ns_ref);
                code_context.root.add_using_directive (ns_ref);
            } else if (_profile == Vala.Profile.GOBJECT) {
                // import the GLib namespace by default (namespace of backend-specific standard library)
                var ns_ref = new Vala.UsingDirective (new Vala.UnresolvedSymbol (null, "GLib", null));
                doc.add_using_directive (ns_ref);
                code_context.root.add_using_directive (ns_ref);
            }

            // clear all comments from file
            doc.get_comments ().clear ();

            // clear all code nodes from file
            doc.get_nodes ().clear ();

            cancellable.set_error_if_cancelled ();
        }

        // packages (should come after in case we've wrapped any package files in TextDocuments)
        foreach (string package in _packages)
            code_context.add_external_package (package);

        Vala.CodeContext.pop ();
    }

    private void compile () throws Error {
        debug ("compiling %s ...", id);
        Vala.CodeContext.push (code_context);
        var vala_parser = new Vala.Parser ();
        var genie_parser = new Vala.Genie.Parser ();
        var gir_parser = new Vala.GirParser ();

        // add all generated files before compiling
        foreach (File generated_file in _generated_sources) {
            // generated files are also part of the project, so we use TextDocument intead of Vala.SourceFile
            try {
                if (!generated_file.query_exists ())
                    throw new FileError.NOENT (@"file does not exist");
                code_context.add_source_file (new TextDocument (code_context, generated_file));
            } catch (Error e) {
                warning ("could not add file for %s: %s - %s", id, generated_file.get_uri (), e.message);

                Vala.CodeContext.pop ();
                throw e;        // rethrow
            }
        }

        // compile everything
        vala_parser.parse (code_context);
        genie_parser.parse (code_context);
        gir_parser.parse (code_context);
        code_context.check ();

        // generate output files
        // generate VAPI
        if (_output_vapi != null) {
            // create the directories if they don't exist
            DirUtils.create_with_parents (Path.get_dirname (_output_vapi), 0755);
            var interface_writer = new Vala.CodeWriter ();
            interface_writer.write_file (code_context, _output_vapi);
        }

        // write output GIR
        if (_output_gir != null) {
            // TODO: output GIR (Vala.GIRWriter is private)
        }

        // write out internal VAPI
        if (_output_internal_vapi != null) {
            // create the directories if they don't exist
            DirUtils.create_with_parents (Path.get_dirname (_output_internal_vapi), 0755);
            var interface_writer = new Vala.CodeWriter (Vala.CodeWriterType.INTERNAL);
            interface_writer.write_file (code_context, _output_internal_vapi);
        }

        // update C name map for package files
        cname_to_sym.clear ();
        foreach (Vala.SourceFile source_file in code_context.get_source_files ()) {
            if (source_file.file_type == Vala.SourceFileType.PACKAGE)
                source_file.accept (new CNameMapper (cname_to_sym));
        }

        // remove analyses for sources that are no longer a part of the code context
        var removed_sources = new Vala.HashSet<Vala.SourceFile> ();
        removed_sources.add_all (code_context.get_source_files ());
        foreach (var entry in _project_sources) {
            var text_document = entry.value;
            text_document.last_fresh_content = text_document.content;
            removed_sources.remove (entry.value);
        }
        foreach (var source in removed_sources)
            _source_analyzers.unset (source, null);

        last_updated = new DateTime.now ();
        _completed_first_compile = true;
        Vala.CodeContext.pop ();
        debug ("finished compiling %s", id);
    }

    public override void build_if_stale (Cancellable? cancellable = null) throws Error {
        if (_project_sources.is_empty)
            // configure for first time
            configure (cancellable);

        bool stale = false;
        foreach (BuildTarget dep in dependencies.values) {
            if (dep.last_updated.compare (last_updated) > 0) {
                stale = true;
                break;
            }
        }
        foreach (TextDocument doc in _project_sources.values) {
            if (doc.last_updated.compare (last_updated) > 0) {
                stale = true;
                break;
            }
        }
        if (stale || !_completed_first_compile) {
            configure (cancellable);
            cancellable.set_error_if_cancelled ();
            // TODO: cancellable compilation
            compile ();
        }
    }

    /**
     * Get the analysis for the source file
     */
    public CodeAnalyzer? get_analysis_for_file<T> (Vala.SourceFile source) {
        var analyses = _source_analyzers[source];
        if (analyses == null) {
            analyses = new HashMap<Type, CodeAnalyzer> ();
            _source_analyzers[source] = analyses;
        }

        // generate the analysis on demand if it doesn't exist or it is stale
        CodeAnalyzer? analysis = null;
        if (!analyses.has_key (typeof (T)) || analyses[typeof (T)].last_updated.compare (last_updated) < 0) {
            Vala.CodeContext.push (code_context);
            if (typeof (T) == typeof (CodeStyleAnalyzer)) {
                analysis = new CodeStyleAnalyzer (source);
            } else if (typeof (T) == typeof (SymbolEnumerator)) {
                analysis = new SymbolEnumerator (source);
            } else if (typeof (T) == typeof (CodeLensAnalyzer)) {
                analysis = new CodeLensAnalyzer (source);
            }

            if (analysis != null) {
                analysis.last_updated = new DateTime.now ();
                analyses[typeof (T)] = analysis;
            }
            Vala.CodeContext.pop ();
        } else {
            analysis = analyses[typeof (T)];
        }

        return analysis;
    }

    public bool lookup_input_source_file (File file, out Vala.SourceFile input_source) {
        string? path = file.get_path ();
        string? filename = path != null ? Util.realpath (path) : null;
        string uri = file.get_uri ();
        foreach (var source_file in code_context.get_source_files ()) {
            if (filename != null && Util.realpath (source_file.filename) == filename || source_file.filename == uri) {
                input_source = source_file;
                return true;
            }
        }
        input_source = null;
        return false;
    }

    public Collection<Vala.SourceFile> get_project_files () {
        return _project_sources.values;
    }
}
