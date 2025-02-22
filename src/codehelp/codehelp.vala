/* codehelp.vala
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

/**
 * Code help utilities that don't belong to any specific class
 */
namespace Vls.CodeHelp {
    /**
     * see `vala/valamemberaccess.vala`
     * This determines whether we can access a symbol in the current scope.
     */
    bool is_symbol_accessible (Vala.Symbol member, Vala.Scope current_scope) {
        if (member.access == Vala.SymbolAccessibility.PROTECTED && member.parent_symbol is Vala.TypeSymbol) {
            var target_type = (Vala.TypeSymbol) member.parent_symbol;
            bool in_subtype = false;

            for (Vala.Symbol? this_symbol = current_scope.owner; 
                 this_symbol != null;
                 this_symbol = this_symbol.parent_symbol) {
                if (this_symbol == target_type) {
                    in_subtype = true;
                    break;
                }

                var cl = this_symbol as Vala.Class;
                if (cl != null && cl.is_subtype_of (target_type)) {
                    in_subtype = true;
                    break;
                }
            }

            return in_subtype;
        } else if (member.access == Vala.SymbolAccessibility.PRIVATE) {
            var target_type = member.parent_symbol;
            bool in_target_type = false;

            for (Vala.Symbol? this_symbol = current_scope.owner;
                 this_symbol != null;
                 this_symbol = this_symbol.parent_symbol) {
                if (this_symbol == target_type) {
                    in_target_type = true;
                    break;
                }
            }

            return in_target_type;
        }
        return true;
    }

    public string get_expression_representation (Vala.CodeNode expr) {
        if (expr is Vala.Literal)
            return expr.to_string ();
        var sr = expr.source_reference;
        if (sr == null)
            return @"(error - $(expr.type_name) does not have source ref!)";
        var file = sr.file;
        unowned string content;
        if (file.content == null)
            file.content = (string) file.get_mapped_contents ();
        if (sr.file is TextDocument) {
            content = ((TextDocument)sr.file).last_fresh_content;
        } else {
            content = file.content;
        }
        var from = (long) Util.get_string_pos (content, sr.begin.line-1, sr.begin.column-1);
        var to = (long) Util.get_string_pos (content, sr.end.line-1, sr.end.column);
        if (from > to) {
            warning ("expression %s has bad source reference %s", expr.to_string (), expr.source_reference.to_string ());
            return expr.to_string ();
        }
        return file.content[from:to];
    }

    /**
     * Look for the symbol name in the current scope or try all ancestor scopes.
     */
    public Vala.Symbol? lookup_in_scope_and_ancestors (Vala.Scope scope, string name) {
        for (var current_scope = scope; current_scope != null; current_scope = current_scope.parent_scope) {
            var found_sym = current_scope.lookup (name);
            if (found_sym != null)
                return found_sym;
        }
        // if (scope.owner.source_reference != null) {
        //     var file = scope.owner.source_reference.file;
        //     foreach (var using_directive in file.current_using_directives) {
        //         var found_sym = using_directive.namespace_symbol.scope.lookup (name);
        //         if (found_sym != null)
        //             return found_sym;
        //     }
        // }
        return null;
    }

    public Vala.Symbol? lookup_symbol_full_name (string full_name, Vala.Scope scope, out Gee.ArrayList<Vala.Symbol> components = null) {
        string[] symbol_names = full_name.split (".");
        Vala.Symbol? current_symbol = lookup_in_scope_and_ancestors (scope, symbol_names[0]);
        components = new Gee.ArrayList<Vala.Symbol> ();

        if (current_symbol != null)
            components.add (current_symbol);

        for (int i = 1; i < symbol_names.length && current_symbol != null; i++) {
            current_symbol = current_symbol.scope.lookup (symbol_names[i]);
            if (current_symbol != null)
                components.add (current_symbol);
        }

        return current_symbol;
    }

    /**
     * Displays a symbol in a format that's contextualized in the current scope.
     */
    private string get_symbol_name_representation (Vala.Symbol symbol, Vala.Scope? scope) {
        var components = new Queue<string> ();
        for (var current_symbol = symbol; current_symbol != null && current_symbol.name != null; current_symbol = current_symbol.parent_symbol) {
            components.push_head (current_symbol.name);
            if (scope != null && lookup_in_scope_and_ancestors (scope, current_symbol.name) == current_symbol) {
                // add the 
                break;
            }
        }

        var builder = new StringBuilder ();
        while (!components.is_empty ()) {
            builder.append (components.pop_head ());
            if (!components.is_empty ())
                builder.append_c ('.');
        }

        return builder.str;
    }

    /**
     * Represent a data type in a format that's contextualized in the current scope.
     */
    private string get_data_type_representation (Vala.DataType data_type, Vala.Scope? scope) {
        var builder = new StringBuilder ();

        if (data_type is Vala.ArrayType) {  // ArrayType is a ReferenceType
            // see ArrayType.to_qualified_string()
            var array_type = (Vala.ArrayType) data_type;
            var elem_str = get_data_type_representation (array_type.element_type, scope);
            if (array_type.element_type.is_weak () && !(array_type.parent_node is Vala.Constant)) {
                elem_str = "(unowned %s)".printf (elem_str);
            }

            if (!array_type.fixed_length)
                return "%s[%s]%s".printf (elem_str, string.nfill (array_type.rank - 1, ','), array_type.nullable ? "?" : "");
            return elem_str;
        } else if (data_type is Vala.ReferenceType && data_type.symbol != null) {
            var reference_type = (Vala.ReferenceType) data_type;
            builder.append (get_symbol_name_representation (reference_type.symbol, scope));
            var type_arguments = reference_type.get_type_arguments ();
            if (!type_arguments.is_empty)
                builder.append_c ('<');
            int i = 1;
            foreach (var type_argument in type_arguments) {
                if (i > 1) {
                    builder.append (", ");
                }
                if (type_argument.is_weak ())
                    builder.append ("weak ");
                builder.append (get_data_type_representation (type_argument, scope));
                i++;
            }
            if (!type_arguments.is_empty)
                builder.append_c ('>');
            if (data_type.nullable)
                builder.append_c ('?');
        } else {
            builder.append (data_type.to_qualified_string ());
        }

        return builder.str;
    }

    /**
     * Get the nearest scope containing this node.
     */
    public Vala.Scope get_scope_containing_node (Vala.CodeNode code_node) {
        Vala.Scope? best = null;

        for (Vala.CodeNode? node = code_node; node != null; node = node.parent_node) {
            if (node is Vala.Symbol) {
                var sym = (Vala.Symbol) node;
                best = sym.scope;
                break;
            }
        }

        assert (best != null);

        return (!) best;
    }

    /**
     * NOTE: if `instance_type` is recursively defined, `parent_symbol` must be
     * referred to by one of the data types in the hierarchy, otherwise this
     * function will never return. Currently, recursively-defined types are
     * disallowed but regardless this function should never be called with a
     * type symbol that does not belong to the hierarchy.
     */
    private Vala.List<Vala.DataType>? get_actual_type_arguments_for_parent_symbol (Vala.DataType instance_type, Vala.TypeSymbol parent_symbol) {
        var search = new Queue<Vala.DataType> ();
        search.push_tail (instance_type);

        while (!search.is_empty ()) {
            var candidate_type = search.pop_head ();

            if (candidate_type.type_symbol == parent_symbol)
                return candidate_type.get_type_arguments ();

            if (candidate_type.type_symbol is Vala.Class) {
                foreach (var base_type in ((Vala.Class)candidate_type.type_symbol).get_base_types ())
                    search.push_tail (base_type.get_actual_type (candidate_type, null, null));
            } else if (candidate_type.type_symbol is Vala.Interface) {
                foreach (var prereq_type in ((Vala.Interface)candidate_type.type_symbol).get_prerequisites ())
                    search.push_tail (prereq_type.get_actual_type (candidate_type, null, null));
            } else if (candidate_type.type_symbol is Vala.Struct) {
                search.push_tail (((Vala.Struct)candidate_type.type_symbol).base_type.get_actual_type (candidate_type, null, null));
            }
        }

        return null;
    }

    /**
     * Represents a callable symbol
     * @param instance_type the type of the instance this method belongs to, or null
     * @param method_type_arguments the type arguments for this method, or null
     * @param allow_show_parent_member whether to show the parent member of the callable symbol
     */
    private string get_callable_representation (Vala.DataType? instance_type, Vala.List<Vala.DataType>? method_type_arguments,
                                                Vala.Callable callable_sym, Vala.Scope? scope, bool show_initializers,
                                                bool allow_show_parent_member,
                                                string? override_name = null, bool is_parent_symbol = false,
                                                Vala.List<Vala.Parameter>? ellipsis_overrides = null) {
        // see `to_prototype_string()` in `valacallabletype.vala`
        var builder = new StringBuilder ();

        if (!is_parent_symbol) {
            if (instance_type == null && !(callable_sym.parent_symbol is Vala.Namespace)) {
                builder.append (callable_sym.access.to_string ());
                builder.append_c (' ');
            }

            if (callable_sym is Vala.Method) {
                var method = (Vala.Method) callable_sym;
                if (method.binding == Vala.MemberBinding.CLASS)
                    builder.append ("class ");
                if (method.is_abstract && instance_type == null)
                    builder.append ("abstract ");
                if (method.is_virtual && instance_type == null)
                    builder.append ("virtual ");
                if (method.is_inline && instance_type == null)
                    builder.append ("inline ");
                if (method.is_extern && instance_type == null)
                    builder.append ("extern ");
                if (method.overrides && instance_type == null)
                    builder.append ("override ");
                if (method.coroutine)
                    builder.append ("async ");
            }

            if (callable_sym is Vala.Delegate) {
                if (override_name == null)
                    builder.append ("delegate ");
            } else if (callable_sym is Vala.Signal) {
                if (((Vala.Signal)callable_sym).is_virtual && instance_type == null)
                    builder.append ("virtual ");
                builder.append ("signal ");
            }
        }

        // some symbols, like constructors, destructors, and other symbols don't have a name
        if (callable_sym is Vala.CreationMethod || callable_sym is Vala.Destructor) {
            if (callable_sym.parent_symbol == null) {
                // this is an error type
                return "<invalid duplicate symbol>";
            }
            string parent_symbol_representation;
            if (instance_type != null && instance_type is Vala.ObjectType)
                parent_symbol_representation = get_data_type_representation (instance_type, scope);
            else
                parent_symbol_representation = get_symbol_name_representation (callable_sym.parent_symbol, scope);
            builder.append (parent_symbol_representation);
            builder.append ("::");
            if (callable_sym is Vala.CreationMethod) {
                if (callable_sym.name == null || callable_sym.name == ".new")
                    builder.append (callable_sym.parent_symbol.name);
                else
                    builder.append (callable_sym.name);
            }
        } else {
            if (!is_parent_symbol) {
                var actual_return_type = callable_sym.return_type.get_actual_type (instance_type, method_type_arguments, callable_sym);
                if (actual_return_type.is_weak ())
                    builder.append ("unowned ");
                builder.append (get_data_type_representation (actual_return_type, scope));
                builder.append_c (' ');
            }
            // print parent symbol
            if (allow_show_parent_member) {
                if (callable_sym.parent_symbol is Vala.TypeSymbol) {
                    Vala.List<Vala.DataType>? parent_type_arguments = null;
                    if (instance_type != null)
                        parent_type_arguments = get_actual_type_arguments_for_parent_symbol (instance_type, (Vala.TypeSymbol)callable_sym.parent_symbol);
                    string? parent_symbol_representation =
                        get_symbol_representation (null, callable_sym.parent_symbol, scope, allow_show_parent_member, parent_type_arguments, null, false, true);
                    builder.append (parent_symbol_representation);
                    builder.append_c ('.');
                } else if (callable_sym.parent_symbol is Vala.Namespace &&
                           callable_sym.parent_symbol.to_string () != "(root namespace)") {
                    builder.append (get_symbol_representation (null, callable_sym.parent_symbol, scope, allow_show_parent_member, null, null, false, true));
                    builder.append_c ('.');
                }
            }
            builder.append (override_name ?? callable_sym.name);
        }

        Vala.List<Vala.TypeParameter>? type_parameters = null;

        if (callable_sym is Vala.Delegate)
            type_parameters = ((Vala.Delegate)callable_sym).get_type_parameters ();
        else if (callable_sym is Vala.Method)
            type_parameters = ((Vala.Method)callable_sym).get_type_parameters ();

        if (type_parameters != null && !type_parameters.is_empty) {
            Vala.List<Vala.DataType>? delegate_type_arguments = null;
            if (instance_type is Vala.DelegateType) {
                var delegate_type = (Vala.DelegateType) instance_type;
                if (delegate_type.delegate_symbol == callable_sym)
                    delegate_type_arguments = delegate_type.get_type_arguments ();
            }

            int i = 1;
            builder.append_c ('<');
            foreach (var type_parameter in type_parameters) {
                if (i > 1) {
                    builder.append_c (',');
                }
                int idx = (callable_sym is Vala.Delegate) ? 
                            ((Vala.Delegate)callable_sym).get_type_parameter_index (type_parameter.name) :
                            ((Vala.Method)callable_sym).get_type_parameter_index (type_parameter.name);
                if (method_type_arguments != null && idx < method_type_arguments.size) {
                    builder.append (get_data_type_representation (method_type_arguments[idx], scope));
                } else if (delegate_type_arguments != null && idx < delegate_type_arguments.size) {
                    builder.append (get_data_type_representation (delegate_type_arguments[idx], scope));
                } else {
                    builder.append (type_parameter.name);
                }
                i++;
            }
            builder.append_c ('>');
        }

        // don't print signature if this is a parent symbol
        // (signals may be parents of .connect() functions)
        if (!is_parent_symbol) {
            builder.append (" (");
            // print parameters
            int i = 1;
            // add sender parameter for internal signal-delegates
            if (callable_sym is Vala.Delegate) {
                var delegate_symbol = (Vala.Delegate) callable_sym;
                if (delegate_symbol.parent_symbol is Vala.Signal && delegate_symbol.sender_type != null) {
                    var actual_sender_type = delegate_symbol.sender_type.get_actual_type (instance_type, method_type_arguments, callable_sym);
                    builder.append (get_data_type_representation (actual_sender_type, scope));
                    i++;
                }
            }

            foreach (Vala.Parameter param in callable_sym.get_parameters ()) {
                if (param.ellipsis) {
                    if (ellipsis_overrides == null) {
                        if (i > 1) {
                            builder.append (", ");
                        }
                        builder.append ("...");
                    } else {
                        foreach (var synthetic_param in ellipsis_overrides) {
                            if (i > 1) {
                                builder.append (", ");
                            }
                            var eo = CodeHelp.get_symbol_representation (null, synthetic_param, scope, false);
                            builder.append (eo);
                            i++;
                        }
                    }
                    continue;
                }

                if (i > 1) {
                    builder.append (", ");
                }

                if (param.params_array) {
                    builder.append ("params ");
                }

                var actual_var_type = param.variable_type.get_actual_type (instance_type, method_type_arguments, callable_sym);

                if (param.direction == Vala.ParameterDirection.IN) {
                    if (actual_var_type.value_owned) {
                        builder.append ("owned ");
                    }
                } else {
                    if (param.direction == Vala.ParameterDirection.REF) {
                        builder.append ("ref ");
                    } else if (param.direction == Vala.ParameterDirection.OUT) {
                        builder.append ("out ");
                    }
                    if (!actual_var_type.value_owned && actual_var_type is Vala.ReferenceType) {
                        builder.append ("weak ");
                    }
                }

                builder.append (get_data_type_representation (actual_var_type, scope));
                // print parameter name
                builder.append_c (' ');
                builder.append (param.name);

                if (param.initializer != null && show_initializers) {
                    builder.append (" = ");
                    builder.append (get_expression_representation (param.initializer));
                }

                i++;
            }

            builder.append_c (')');

            // Append error-types
            var error_types = new Vala.ArrayList<Vala.DataType> ();
            callable_sym.get_error_types (error_types);
            if (error_types.size > 0) {
                builder.append (" throws ");

                bool first = true;
                foreach (Vala.DataType type in error_types) {
                    if (!first) {
                        builder.append (", ");
                    } else {
                        first = false;
                    }

                    builder.append (get_data_type_representation (type, scope));
                }
            }
        }

        return builder.str;
    }

    /**
     * Represents a variable symbol
     */
    private string get_variable_representation (Vala.DataType? data_type, Vala.List<Vala.DataType>? method_type_arguments,
                                                Vala.Variable variable_sym, Vala.Scope? scope, string? override_name,
                                                bool allow_show_parent_member,
                                                bool show_initializer,
                                                bool show_parameter_direction) {
        Vala.DataType? actual_var_type = variable_sym.variable_type.get_actual_type (data_type, method_type_arguments, variable_sym);
        var builder = new StringBuilder ();
        if (!(variable_sym is Vala.Parameter)) {
            if (variable_sym is Vala.Field && ((Vala.Field)variable_sym).binding == Vala.MemberBinding.CLASS)
                builder.append ("class ");
            if (actual_var_type.is_weak ())
                builder.append ((variable_sym is Vala.Field) ? "weak " : "unowned ");
        } else if (variable_sym is Vala.Parameter) {
            var param = (Vala.Parameter) variable_sym;
            if (param.direction == Vala.ParameterDirection.OUT) {
                if (show_parameter_direction)
                    builder.append ("out ");
            } else if (param.direction == Vala.ParameterDirection.REF) {
                if (show_parameter_direction)
                    builder.append ("ref ");
            } else if (actual_var_type.value_owned) {
                builder.append ("owned ");
            }
        }
        builder.append (get_data_type_representation (actual_var_type, scope));
        builder.append_c (' ');
        // print parent symbol
        if (allow_show_parent_member) {
            if (variable_sym.parent_symbol is Vala.TypeSymbol) {
                Vala.List<Vala.DataType>? parent_type_arguments = null;
                if (data_type != null)
                    parent_type_arguments = get_actual_type_arguments_for_parent_symbol (data_type, (Vala.TypeSymbol)variable_sym.parent_symbol);
                string? parent_symbol_representation =
                    get_symbol_representation (null, variable_sym.parent_symbol, scope, allow_show_parent_member, parent_type_arguments, null, false, true);
                builder.append (parent_symbol_representation);
                builder.append_c ('.');
            } else if (variable_sym.parent_symbol is Vala.Namespace &&
                       variable_sym.parent_symbol.to_string () != "(root namespace)") {
                builder.append (get_symbol_representation (null, variable_sym.parent_symbol, scope, allow_show_parent_member, null, null, false, true));
                builder.append_c ('.');
            }
        }
        builder.append (override_name ?? variable_sym.name);
        if (variable_sym.initializer != null && show_initializer) {
            Vala.ForeachStatement? foreach_statement = null;
            if (variable_sym is Vala.LocalVariable) {
                for (Vala.CodeNode? current_node = variable_sym; current_node != null; current_node = current_node.parent_node) {
                    foreach_statement = current_node as Vala.ForeachStatement;
                    if (foreach_statement != null) {
                        break;
                    }
                }
            }
            if (foreach_statement != null && variable_sym.name == foreach_statement.variable_name) {
                builder.append (" in ");
                builder.append (get_expression_representation (foreach_statement.collection));
            } else {
                builder.append (" = ");
                builder.append (get_expression_representation (variable_sym.initializer));
            }
        }
        return builder.str;       
    }

    /**
     * Get a representation of a property
     */
    private string get_property_representation (Vala.DataType? data_type, Vala.List<Vala.DataType>? method_type_arguments,
                                                Vala.Property property_sym,
                                                Vala.Scope? scope, bool allow_show_parent_member, bool show_initializer) {
        var actual_property_type = property_sym.property_type.get_actual_type (data_type, method_type_arguments, property_sym);
        var builder = new StringBuilder ();

        if (data_type == null && !(property_sym.parent_symbol is Vala.Namespace)) {
            builder.append (property_sym.access.to_string ());
            builder.append_c (' ');
        }

        if (property_sym.binding == Vala.MemberBinding.CLASS)
            builder.append ("class ");
        if (property_sym.is_abstract && data_type == null)
            builder.append ("abstract ");
        if (property_sym.is_virtual && data_type == null)
            builder.append ("virtual ");
        if (property_sym.is_extern && data_type == null)
            builder.append ("extern ");
        if (property_sym.overrides && data_type == null)
            builder.append ("override ");

        if (actual_property_type.is_weak ())
            builder.append ("weak ");
        builder.append (get_data_type_representation (actual_property_type, scope));
        builder.append_c (' ');
        // print parent symbol
        if (allow_show_parent_member) {
            if (property_sym.parent_symbol is Vala.TypeSymbol) {
                Vala.List<Vala.DataType>? parent_type_arguments = null;
                if (data_type != null)
                    parent_type_arguments = get_actual_type_arguments_for_parent_symbol (data_type, (Vala.TypeSymbol)property_sym.parent_symbol);
                string? parent_symbol_representation =
                    get_symbol_representation (null, property_sym.parent_symbol, scope, allow_show_parent_member, parent_type_arguments, null, false, true);
                builder.append (parent_symbol_representation);
                builder.append_c ('.');
            } else if (property_sym.parent_symbol is Vala.Namespace &&
                       property_sym.parent_symbol.to_string () != "(root namespace)") {
                builder.append (get_symbol_representation (null, property_sym.parent_symbol, scope, allow_show_parent_member, null, null, false, true));
                builder.append_c ('.');
            }
        }
        builder.append (property_sym.name);
        builder.append (" {");
        if (property_sym.get_accessor != null) {
            if (property_sym.access != property_sym.get_accessor.access) {
                builder.append_c (' ');
                builder.append (property_sym.get_accessor.access.to_string ());
            }
            if (property_sym.get_accessor.value_type is Vala.ReferenceType &&
                property_sym.get_accessor.value_type.value_owned)
                builder.append (" owned");
            builder.append (" get;");
        }
        if (property_sym.set_accessor != null) {
            if (property_sym.access != property_sym.set_accessor.access) {
                builder.append_c (' ');
                builder.append (property_sym.set_accessor.access.to_string ());
            }
            if (property_sym.set_accessor.construction)
                builder.append (" construct");
            if (property_sym.set_accessor.writable)
                builder.append (" set;");
            else
                builder.append (";");
        }
        if (property_sym.initializer != null && show_initializer) {
            builder.append (" default = ");
            builder.append (get_expression_representation (property_sym.initializer));
            builder.append_c (';');
        }
        builder.append (" }");
        return builder.str;
    }

    private string get_constant_representation (Vala.DataType? data_type, Vala.Constant constant_sym, Vala.Scope? scope,
                                                bool show_initializer = true) {
        var builder = new StringBuilder ();
        if (constant_sym.value == null && data_type != null && !(constant_sym is Vala.EnumValue)) {
            builder.append_c ('(');
            builder.append ("const ");
            builder.append (get_data_type_representation (data_type, scope));
            builder.append (") ");
        } else if (constant_sym.type_reference != null) {
            if (!(constant_sym is Vala.EnumValue))
                builder.append ("const ");
            builder.append (get_data_type_representation (constant_sym.type_reference, scope));
            builder.append_c (' ');
        }
        builder.append (get_symbol_name_representation (constant_sym, scope));
        if (constant_sym.value != null && show_initializer) {
            builder.append (" = ");
            builder.append (get_expression_representation (constant_sym.value));
        }
        return builder.str;
    }

    /**
     * Get the string representation of a symbol.
     * @param data_type either the data type containing the symbol, or the parent data type, or null if none
     * @param sym the symbol to represent (can be null if data_type is non-null)
     */
    public string? get_symbol_representation (Vala.DataType? data_type, Vala.Symbol? sym, 
                                              Vala.Scope? scope,
                                              bool allow_show_parent_member,
                                              Vala.List<Vala.DataType>? method_type_arguments = null,
                                              string? override_name = null, bool show_initializers = true,
                                              bool is_parent_symbol = false,
                                              Vala.List<Vala.Parameter>? ellipsis_overrides = null,
                                              bool show_parameter_direction = true) {
        if (data_type == null && sym == null)
            return null;
        if (data_type == null || sym != null && SymbolReferences.get_symbol_data_type_refers_to (data_type) == sym) {
            if (sym is Vala.Namespace)
                return (!is_parent_symbol ? "namespace " : "") + get_symbol_name_representation(sym, scope);
            else if (sym is Vala.Callable) {
                return get_callable_representation (data_type, method_type_arguments, (Vala.Callable) sym, scope, show_initializers, allow_show_parent_member, null, is_parent_symbol, ellipsis_overrides);
            } else if (sym is Vala.Variable) {
                if (sym is Vala.Parameter && ((Vala.Parameter)sym).ellipsis)
                    return "...";
                return get_variable_representation (data_type, method_type_arguments, (Vala.Variable) sym, scope, override_name, show_initializers, allow_show_parent_member, show_parameter_direction);
            } else if (sym is Vala.TypeSymbol) {
                var builder = new StringBuilder ();
                Vala.DataType? actual_data_type = null;

                if (sym is Vala.Struct) {
                    if (!is_parent_symbol)
                        builder.append ("struct ");
                    actual_data_type = new Vala.StructValueType ((Vala.Struct) sym);
                } else if (sym is Vala.Enum) {
                    if (!is_parent_symbol)
                        builder.append ("enum ");
                } else if (sym is Vala.ErrorDomain) {
                    if (!is_parent_symbol)
                        builder.append ("errordomain ");
                } else if (sym is Vala.Interface) {
                    if (!is_parent_symbol)
                        builder.append ("interface ");
                    actual_data_type = new Vala.InterfaceType ((Vala.Interface) sym);
                } else if (sym is Vala.Class) {
                    if (!is_parent_symbol) {
                        if (((Vala.Class)sym).is_abstract)
                            builder.append ("abstract ");
                        builder.append ("class ");
                    }
                    actual_data_type = new Vala.ClassType ((Vala.Class) sym);
                }

                // print name with type parameters
                builder.append (get_symbol_name_representation (sym, scope));
                Vala.List<Vala.DataType>? type_arguments = method_type_arguments;
                if (type_arguments == null && data_type != null)
                    type_arguments = data_type.get_type_arguments ();
                Vala.List<Vala.TypeParameter> type_parameters = new Vala.ArrayList<Vala.TypeParameter> ();

                if (sym is Vala.ObjectTypeSymbol)
                    type_parameters = ((Vala.ObjectTypeSymbol)sym).get_type_parameters ();
                else if (sym is Vala.Struct)
                    type_parameters = ((Vala.Struct)sym).get_type_parameters ();

                int i = 1;
                if (!type_parameters.is_empty)
                    builder.append_c ('<');
                foreach (var type_parameter in type_parameters) {
                    if (i > 1) {
                        builder.append (", ");
                    }

                    int type_param_idx = ((Vala.TypeSymbol)sym).get_type_parameter_index (type_parameter.name);
                    if (type_arguments != null && type_param_idx < type_arguments.size) {
                        if (type_arguments[type_param_idx].is_weak ())
                            builder.append ("weak ");
                        builder.append (get_data_type_representation (type_arguments[type_param_idx], scope));
                        actual_data_type.add_type_argument (type_arguments[type_param_idx].copy ());
                    } else {
                        builder.append (type_parameter.name);
                    }
                    i++;
                }
                if (!type_parameters.is_empty)
                    builder.append_c ('>');

                if (!is_parent_symbol) {
                    // print base types
                    Vala.List<Vala.DataType> base_types = new Vala.ArrayList<Vala.DataType> ();
                    if (sym is Vala.Class)
                        base_types = ((Vala.Class)sym).get_base_types ();
                    else if (sym is Vala.Interface)
                        base_types = ((Vala.Interface)sym).get_prerequisites ();
                    
                    i = 1;
                    if (!base_types.is_empty)
                        builder.append (": ");

                    foreach (var base_type in base_types) {
                        if (i > 1) {
                            builder.append (", ");
                        }
                        var actual_base_type = base_type.get_actual_type (actual_data_type, method_type_arguments, sym);
                        builder.append (get_data_type_representation (actual_base_type, scope));
                        i++;
                    }
                }

                return builder.str;
            } else if (sym is Vala.Constant) {
                return get_constant_representation (data_type, (Vala.Constant) sym, scope);
            } else if (sym is Vala.Property) {
                return get_property_representation (data_type, method_type_arguments, (Vala.Property) sym, scope, allow_show_parent_member, show_initializers);
            } else if (sym is Vala.Constructor) {
                // do nothing for construct blocks
                return null;
            } else if (sym is Vala.Destructor) {
                var builder = new StringBuilder ();
                string parent_symbol_representation = get_symbol_name_representation (sym.parent_symbol, scope);
                builder.append (parent_symbol_representation);
                builder.append ("::~");
                builder.append (sym.name ?? sym.parent_symbol.name);
                builder.append (" ()");
                return builder.str;
            } else if (sym is Vala.TypeParameter) {
                var builder = new StringBuilder ();
                string parent_symbol_representation = get_symbol_name_representation (sym.parent_symbol, scope);
                builder.append (sym.name);
                builder.append (" (type parameter of ");
                builder.append (parent_symbol_representation);
                builder.append_c (')');
                return builder.str;
            }
            warning ("symbol %s unmatched", sym.type_name);
            return null;
        }

        // just a datatype
        if (sym == null) {
            if (data_type is Vala.DelegateType)
                return get_callable_representation (data_type, method_type_arguments,
                    ((Vala.DelegateType)data_type).delegate_symbol, scope, true, allow_show_parent_member, null, is_parent_symbol, ellipsis_overrides);
            return get_data_type_representation (data_type, scope);
        }

        // we have a data type with a symbol

        if (sym is Vala.Callable)
            return get_callable_representation (data_type, method_type_arguments, (Vala.Callable)sym, scope, show_initializers, allow_show_parent_member, null, is_parent_symbol, ellipsis_overrides);
        
        if (sym is Vala.Parameter && ((Vala.Parameter)sym).ellipsis)
            return "...";

        if (sym is Vala.Variable) {
            if (data_type is Vala.DelegateType && ((Vala.Variable)sym).variable_type.equals (data_type)) {
                return get_callable_representation (data_type, method_type_arguments,
                    ((Vala.DelegateType)data_type).delegate_symbol, scope, true, allow_show_parent_member, sym.name, is_parent_symbol, ellipsis_overrides);
            }
            return get_variable_representation (data_type, method_type_arguments, (Vala.Variable)sym, scope, override_name, show_initializers, allow_show_parent_member, show_parameter_direction);
        }

        if (sym is Vala.Property)
            return get_property_representation (data_type, method_type_arguments, (Vala.Property)sym, scope, allow_show_parent_member, show_initializers);
        
        if (sym is Vala.Constant)
            return get_constant_representation (data_type, (Vala.Constant)sym, scope);

        if (sym is Vala.ErrorCode)
            return get_symbol_name_representation (sym, scope);

        critical ("uncaught data type with symbol (%s with %s as %s)", data_type.to_string (), sym.name, sym.type_name);
        return null;
    }

    private bool is_snake_case_symbol (Vala.Symbol sym) {
        return sym is Vala.Method || sym is Vala.Property || sym is Vala.Field ||
            sym is Vala.EnumValue || sym is Vala.ErrorCode || sym is Vala.Constant ||
            sym is Vala.Signal;
    }

    /**
     * Gets the C name of a symbol.
     */
    public string get_symbol_cname (Vala.Symbol sym) {
        string? cname = null;

        if ((cname = sym.get_attribute_string ("CCode", "cname")) != null)
            return cname;
        
        var cname_sb = new StringBuilder ();
        bool to_snake_case = is_snake_case_symbol (sym);
        bool all_caps = sym is Vala.EnumValue || sym is Vala.ErrorCode || sym is Vala.Constant;

        for (var current_sym = sym; current_sym != null && current_sym.name != null; current_sym = current_sym.parent_symbol) {
            string component = current_sym.name;
            if (current_sym is Vala.CreationMethod) {
                if (component == ".new")
                    component = "new";
                else
                    component = "new_" + component;
            }
            if (to_snake_case) {
                string? lower_case_cprefix = null;
                string? cprefix = current_sym.get_attribute_string ("CCode", "cprefix");
                if ((lower_case_cprefix = current_sym.get_attribute_string ("CCode", "lower_case_cprefix")) != null ||
                    cprefix != null && cprefix.contains ("_")) {
                    component = lower_case_cprefix ?? cprefix;
                    cname_sb.prepend (all_caps ? component.up () : component);
                    break;
                } else if (!is_snake_case_symbol (current_sym)) {
                    component = Vala.Symbol.camel_case_to_lower_case (component);
                }
                if (cname_sb.len > 0)
                    cname_sb.prepend_c ('_');
            } else {
                string? cprefix = null;
                if ((cprefix = current_sym.get_attribute_string ("CCode", "cprefix")) != null &&
                    !cprefix.contains ("_")) {
                    cname_sb.prepend (all_caps ? cprefix.up () : cprefix);
                    break;
                }
            }
            cname_sb.prepend (all_caps && current_sym != sym ? component.up () : component);
        }

        return cname_sb.str;
    }

    /**
     * Checks two namespace {@link Vala.CodeNode}s for equality, since namespaces
     * can be defined in multiple places and therefore a simple pointer equality
     * test will not work. This will also return false if any of the arguments
     * is not a {@link Vala.Namespace}
     */
    bool namespaces_equal (Vala.CodeNode node1, Vala.CodeNode node2) {
        var ns1 = node1 as Vala.Namespace;
        var ns2 = node2 as Vala.Namespace;

        if (ns1 == null || ns2 == null)
            return false;

        if (ns1.name == ns2.name) {
            if ((ns1.parent_symbol == null || ns1.parent_symbol.get_full_name () == null) !=
                    (ns2.parent_symbol == null || ns2.parent_symbol.get_full_name () == null))
                return false;
            if ((ns1.parent_symbol == null || ns1.parent_symbol.get_full_name () == null) &&
                    (ns2.parent_symbol == null || ns2.parent_symbol.get_full_name () == null))
                return true;
            return namespaces_equal (ns1.parent_symbol, ns2.parent_symbol);
        }

        return false;
    }

    static bool base_method_requires_override (Vala.Method m) {
        return m.is_virtual || m.is_abstract && m.parent_symbol is Vala.Class && ((Vala.Class)m.parent_symbol).is_abstract;
    }

    static bool base_property_requires_override (Vala.Property p) {
        return p.is_virtual || p.is_abstract && p.parent_symbol is Vala.Class && ((Vala.Class)p.parent_symbol).is_abstract;
    }
}
