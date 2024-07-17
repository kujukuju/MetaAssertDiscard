get_plugin :: (valid_function_names: [$N] string) -> *Metaprogram_Plugin {
    plugin := New(AssertDiscardPlugin);

    plugin.before_intercept = before_intercept;
    plugin.message = message;
    plugin.shutdown = shutdown;
    plugin.valid_function_names = array_copy(valid_function_names);

    return plugin;
}

#scope_module

before_intercept :: (plugin: *Metaprogram_Plugin, flags: *Intercept_Flags) {
    // it seems like flags should be adding checks, not removing them?
    // reducing complexity like this could conflict with other plugins
    // flags.* |= .SKIP_DECLARATIONS | .SKIP_STRUCTS | .SKIP_OTHERS;
}

message :: (metaprogram_plugin: *Metaprogram_Plugin, message: *Message) {
    plugin := cast(*AssertDiscardPlugin) metaprogram_plugin;

    if message.kind == {
        case .TYPECHECKED;
            start := seconds_since_init();
            defer plugin.duration += seconds_since_init() - start;

            typechecked := cast(*Message_Typechecked) message;
            for typechecked_body: typechecked.procedure_bodies {
                for subexpression: typechecked_body.subexpressions {
                    if subexpression.kind == .PROCEDURE_CALL {
                        subexpression_call := cast(*Code_Procedure_Call) subexpression;

                        // call_expression := subexpression_call.procedure_expression;
                        // if call_expression && call_expression.kind == .PROCEDURE_HEADER {
                        //     subexpression_header := cast(*Code_Procedure_Header) call_expression;

                        //     if !check_valid_procedure_call(plugin, subexpression_header, subexpression_call) {
                        //         compiler_report(plugin, "Found invalid call to assert. You cannot have function calls directly in your assert parameters.", subexpression_call.location, .ERROR);
                        //     }

                        //     continue;
                        // }

                        resolved_call_expression := subexpression_call.resolved_procedure_expression;
                        if resolved_call_expression && resolved_call_expression.kind == .PROCEDURE_HEADER {
                            subexpression_header := cast(*Code_Procedure_Header) resolved_call_expression;

                            invalid_name: string;
                            if !check_valid_procedure_call(plugin, subexpression_header, subexpression_call, *invalid_name) {
                                compiler_report(plugin, tprint("Found invalid call to assert. You cannot have function calls directly in your assert parameters. %", invalid_name), subexpression_call.location, .ERROR);
                            }

                            continue;
                        }
                    }
                }
            }

        case .COMPLETE;
            if plugin.failed {
                print("Found invalid functions inside asserts:\n");
                for _, name: plugin.found_invalid_function_names {
                    print("\t%\n", name);
                }
                compiler_set_workspace_status(.FAILED, plugin.workspace);
            }
    }
}

shutdown :: (plugin: *Metaprogram_Plugin) {
    assert_discard_plugin := cast(*AssertDiscardPlugin) plugin;

    print("Assert discard check took % seconds.\n", assert_discard_plugin.duration);
}

#scope_file

AssertDiscardPlugin :: struct {
    #as using base: Metaprogram_Plugin;

    found_invalid_function_names: Table(string, bool);
    valid_function_names: [] string;
    duration: float64;
    failed: bool;
    
}

check_valid_procedure_call :: (plugin: *AssertDiscardPlugin, header: *Code_Procedure_Header, call: *Code_Procedure_Call, name: *string) -> bool {
    if header.name == "assert" {
        return !caller_contains_function(plugin, call, name);
    }
    
    return true;
}

caller_contains_function :: (plugin: *AssertDiscardPlugin, procedure_call: *Code_Procedure_Call, name: *string) -> bool {
    #import "Compiler";

    contains_procedure_call :: (plugin: *AssertDiscardPlugin, node: *Code_Node, name: *string) -> bool {
        if !node {
            return false;
        }

        if node.kind == .PROCEDURE_CALL {
            procedure_call := cast(*Code_Procedure_Call) node;
            resolved_expression := procedure_call.resolved_procedure_expression;
            procedure_name: string;
            if resolved_expression && resolved_expression.kind == .PROCEDURE_HEADER {
                procedure_header := cast(*Code_Procedure_Header) resolved_expression;
                procedure_name = procedure_header.name;
                if array_find(plugin.valid_function_names, procedure_header.name) {
                    return false;
                }

                table_set(*plugin.found_invalid_function_names, procedure_header.name, true);
            }

            name.* = procedure_name;
            return true;
        } else if node.kind == .BINARY_OPERATOR {
            binary_operator := cast(*Code_Binary_Operator) node;
            return contains_procedure_call(plugin, binary_operator.left, name) || contains_procedure_call(plugin, binary_operator.right, name);
        } else if node.kind == .UNARY_OPERATOR {
            unary_operator := cast(*Code_Unary_Operator) node;
            return contains_procedure_call(plugin, unary_operator.subexpression, name);
        } else if node.kind == .IDENT {
            ident := cast(*Code_Ident) node;
            return contains_procedure_call(plugin, ident.resolved_declaration, name);
        } else if node.kind == .CAST {
            cast_node := cast(*Code_Cast) node;
            return contains_procedure_call(plugin, cast_node.expression, name);
        } else if node.kind == .LITERAL {
            return false;
        } else if node.kind == .DECLARATION {
            // declaration basically means it was defined outside the function call
            return false;
        } else if node.kind == .TYPE_QUERY {
            return false;
        } else if node.kind == .DIRECTIVE_RUN {
            return false;
        }

        print("Unhandled assert arg type. %\n", node.kind);
        return true;
    }

    arguments_unsorted := procedure_call.arguments_unsorted;

    return contains_procedure_call(plugin, arguments_unsorted[0].expression, name);
}

compiler_report :: (plugin: *AssertDiscardPlugin, error_text: string, location: Code_Node.Location, mode := Report.ERROR) {
    loc: Source_Code_Location;
    loc.fully_pathed_filename = location.enclosing_load.fully_pathed_filename;
    loc.line_number           = location.l0;
    loc.character_number      = location.c0;

    compiler_report(error_text, loc, mode);

    if !plugin.failed && (mode == .ERROR || mode == .ERROR_CONTINUABLE) {
        plugin.failed = true;
    }
}

#import "Basic";
#import "Code_Visit";
#import "Compiler";
#import "Hash_Table";
#import "String";