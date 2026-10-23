"""Generate the flat MLWorks project format used by native batch staging."""

def project_text(project_name, names, entry, library_path):
    if not names or entry not in names:
        raise ValueError('project entry must be one of its source files')
    if any('\n' in value or '\r' in value for value in [project_name, library_path, *names]):
        raise ValueError('project fields must occupy one line')
    template = """MLWorks 2.0
batch-probe.mlp 41 7
  AboutInfo 2 2
    Version 0 0
    Description 0 0
  Files 4 0
    prelude.sml
    subset_result.sml
    subset_list.sml
    batch_probe.sml
  Subprojects 0 0
  Targets 3 1
    Details 1 0
      batch_probe.sml OBJECT_FILE
    batch_probe.sml
  Modes 19 2
    Debug 8 2
      Location 1 0
        Debug
      Flags 5 0
        generate_interruptable_code true
        generate_interceptable_code true
        generate_debug_info true
        generate_variable_debug_info true
        mips_r4000 true
    Release 8 2
      Location 1 0
        Release
      Flags 5 0
        generate_interruptable_code true
        optimize_leaf_fns true
        optimize_tail_calls true
        optimize_self_tail_calls true
        mips_r4000 true
    Release
  Configurations 0 0
  Locations 6 3
    LibraryPath 1 0
      LIBRARY_PATH
    Objects 1 0
      objects
    Binaries 1 0
      
"""
    return (template.replace('batch-probe.mlp 41 7', f'{project_name} {37 + len(names)} 7')
        .replace('  Files 4 0\n    prelude.sml\n    subset_result.sml\n    subset_list.sml\n    batch_probe.sml',
                 f'  Files {len(names)} 0\n' + '\n'.join('    ' + name for name in names))
        .replace('batch_probe.sml OBJECT_FILE', entry + ' OBJECT_FILE')
        .replace('    batch_probe.sml\n  Modes', '    ' + entry + '\n  Modes')
        .replace('LIBRARY_PATH', library_path))
