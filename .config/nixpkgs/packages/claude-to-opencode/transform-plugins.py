#!/usr/bin/env python3
"""Transform Claude Code plugins to OpenCode format.

This script transforms Claude Code plugin files (commands, skills, agents)
to be compatible with OpenCode's format.

Transformations applied:
- Model names: haiku/sonnet/opus -> full Vertex AI model IDs
- argument-hint: Appended to description as "Args: <hint>"
- allowed-tools: Removed (no OpenCode equivalent for commands)
- tools (agents): Transformed to OpenCode tools object + permission.skill
- color: Removed (not supported)
- mode: Added 'subagent' for agents
- name: Prefixed with plugin name (skills: plugin-name, agents: plugin.name)
- $ARGS -> $ARGUMENTS
- /plugin:cmd -> /plugin.cmd
- Skill(plugin:skill) -> plugin-skill skill
"""

import sys
import os
import re
import shutil
import yaml


# Model mapping: Claude Code short names -> Vertex AI full IDs
MODEL_MAP = {
    'haiku': 'google-vertex-anthropic/claude-haiku-4-5@20251001',
    'sonnet': 'google-vertex-anthropic/claude-sonnet-4-5@20250929',
    'opus': 'google-vertex-anthropic/claude-opus-4-5@20251101',
}

# Tool mapping: Claude Code names -> OpenCode names
TOOL_MAP = {
    'bash': 'bash',
    'read': 'read',
    'write': 'edit',
    'edit': 'edit',
    'grep': 'grep',
    'glob': 'glob',
    'webfetch': 'webfetch',
    'list': 'list',
}

# Characters that need quoting in YAML values
# Includes colon (:) because it's interpreted as key-value separator in YAML
YAML_SPECIAL_CHARS = set('*&!|>\'\"{}[]#%@`:')


def needs_yaml_quoting(value):
    """Check if a string value needs quoting for YAML safety."""
    if not isinstance(value, str):
        return False
    # Check for YAML special characters that could be misinterpreted
    return any(c in value for c in YAML_SPECIAL_CHARS)


def yaml_safe_dump(data):
    """Dump YAML with proper quoting for values containing special characters.
    
    This prevents issues like '*CRITICAL:' being interpreted as a YAML alias.
    """
    # Custom representer for strings that need quoting
    class SafeDumper(yaml.SafeDumper):
        pass
    
    def str_representer(dumper, data):
        # Use literal block style for multi-line strings
        if '\n' in data:
            return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
        # Use double quotes for strings with special chars
        if needs_yaml_quoting(data):
            return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='"')
        return dumper.represent_scalar('tag:yaml.org,2002:str', data)
    
    SafeDumper.add_representer(str, str_representer)
    
    return yaml.dump(data, Dumper=SafeDumper, default_flow_style=False, 
                     sort_keys=False, allow_unicode=True)


def is_yaml_key_value(line):
    """Check if a line looks like a YAML key: value pair.
    
    A valid YAML key starts with a letter or underscore, followed by
    alphanumerics, hyphens, or underscores, then a colon.
    """
    stripped = line.strip()
    return bool(re.match(r'^[a-zA-Z_][a-zA-Z0-9_-]*:', stripped))


def fix_malformed_frontmatter(frontmatter_str):
    """Fix malformed frontmatter where lines after a field aren't proper YAML.
    
    Some source files have malformed YAML like:
    
        ---
        name: foo
        description: Short description
        
        **CRITICAL: This must be done...
        - Do NOT do this
        **Why**: Because reasons
        ---
    
    The lines starting with ** or - are intended to be part of the description
    but aren't properly formatted as a YAML multi-line string. This function
    detects such orphaned lines and merges them into the description field.
    """
    lines = frontmatter_str.strip().split('\n')
    
    # First pass: identify all key-value pairs and orphaned lines
    key_values = {}  # key -> (line_index, value)
    orphaned_lines = []  # (line_index, content)
    last_key = None
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        if not stripped:
            # Empty line - could be paragraph break in description
            if last_key == 'description':
                orphaned_lines.append((i, ''))
            continue
        
        if is_yaml_key_value(stripped):
            # Extract key and value
            colon_idx = stripped.index(':')
            key = stripped[:colon_idx]
            value = stripped[colon_idx + 1:].strip()
            key_values[key] = (i, value)
            last_key = key
        else:
            # Orphaned line - not a valid key-value pair
            orphaned_lines.append((i, stripped))
    
    # If no orphaned lines, return as-is
    if not orphaned_lines:
        return frontmatter_str
    
    # Check if orphaned lines should be merged into description
    if 'description' not in key_values:
        # No description field to merge into - return as-is
        return frontmatter_str
    
    desc_idx, desc_value = key_values['description']
    
    # Find orphaned lines that come after the description
    orphaned_after_desc = [(idx, content) for idx, content in orphaned_lines 
                           if idx > desc_idx]
    
    if not orphaned_after_desc:
        return frontmatter_str
    
    # Build the merged description as a multi-line string
    desc_parts = [desc_value] if desc_value else []
    for _, content in orphaned_after_desc:
        desc_parts.append(content)
    
    merged_description = '\n'.join(desc_parts)
    
    # Rebuild the frontmatter with the merged description
    result_lines = []
    skip_indices = {idx for idx, _ in orphaned_after_desc}
    
    for i, line in enumerate(lines):
        if i in skip_indices:
            continue
        
        stripped = line.strip()
        if not stripped:
            # Only keep empty lines that aren't between description and orphaned content
            if i < desc_idx or i > max(idx for idx, _ in orphaned_after_desc):
                result_lines.append(line)
            continue
        
        if stripped.startswith('description:'):
            # Replace with multi-line description using literal block scalar
            result_lines.append('description: |')
            for desc_line in merged_description.split('\n'):
                result_lines.append(f'  {desc_line}')
        else:
            result_lines.append(line)
    
    return '\n'.join(result_lines)


def parse_tools_line(tools_line):
    """Parse Claude Code tools line.
    
    Returns:
        tuple: (set of tool names, list of skill references as 'plugin-skill')
    """
    tools = set()
    skills = []
    
    for item in tools_line.split(','):
        item = item.strip()
        if not item:
            continue
        
        # Check for Skill(plugin:skill) pattern
        skill_match = re.match(r'Skill\(([^:]+):([^)]+)\)', item, re.IGNORECASE)
        if skill_match:
            plugin, skill = skill_match.groups()
            skills.append(f"{plugin}-{skill}")
            continue
        
        # Regular tool - map to OpenCode name
        tool_lower = item.lower()
        if tool_lower in TOOL_MAP:
            tools.add(TOOL_MAP[tool_lower])
    
    return tools, skills


def transform_frontmatter_regex(frontmatter_str, plugin_name, file_type):
    """Transform frontmatter using regex when YAML parsing fails.
    
    This handles cases where the YAML has unquoted colons in values.
    """
    lines = frontmatter_str.strip().split('\n')
    result_lines = []
    
    # First pass: extract values we need for transformations
    argument_hint = None
    description = None
    description_line_idx = None
    tools_line = None
    tools_line_idx = None
    
    for i, line in enumerate(lines):
        if line.startswith('argument-hint:'):
            match = re.match(r'^argument-hint:\s*(.+)$', line)
            if match:
                argument_hint = match.group(1).strip()
        elif line.startswith('description:'):
            match = re.match(r'^description:\s*(.+)$', line)
            if match:
                description = match.group(1).strip()
                description_line_idx = i
        elif line.startswith('tools:'):
            match = re.match(r'^tools:\s*(.+)$', line)
            if match:
                tools_line = match.group(1).strip()
                tools_line_idx = i
    
    for i, line in enumerate(lines):
        # Skip empty lines
        if not line.strip():
            result_lines.append(line)
            continue
        
        # Transform model names
        if line.startswith('model:'):
            for short, full in MODEL_MAP.items():
                if f'model: {short}' in line or f'model:{short}' in line:
                    line = f'model: {full}'
                    break
        
        # Remove unsupported fields (but capture argument-hint value first - done above)
        if any(line.startswith(f'{field}:') for field in ['argument-hint', 'color', 'allowed-tools']):
            continue
        
        # Handle description with argument-hint appending (for commands)
        if file_type == 'command' and i == description_line_idx and argument_hint:
            if description:
                # Strip trailing punctuation to avoid double periods
                desc_clean = description.rstrip('.!? ')
                line = f'description: "{desc_clean}. Args: {argument_hint}"'
            else:
                line = f'description: "Args: {argument_hint}"'
        # Quote description if it contains special characters (colons, etc.)
        elif i == description_line_idx and description:
            if needs_yaml_quoting(description):
                # Escape any existing double quotes
                safe_desc = description.replace('"', '\\"')
                line = f'description: "{safe_desc}"'
        
        # Transform tools field for agents
        if file_type == 'agent' and i == tools_line_idx and tools_line:
            tools_enabled, skill_refs = parse_tools_line(tools_line)
            
            # Build tools dict as YAML
            tools_parts = []
            for tool in ['bash', 'read', 'grep', 'glob', 'list', 'webfetch']:
                if tool in tools_enabled:
                    tools_parts.append(f'{tool}: true')
            if 'edit' not in tools_enabled:
                tools_parts.append('edit: false')
            
            if tools_parts:
                result_lines.append('tools:')
                for part in tools_parts:
                    result_lines.append(f'  {part}')
            
            # Add permission.skill for skill refs
            if skill_refs:
                result_lines.append('permission:')
                result_lines.append('  skill:')
                for skill in skill_refs:
                    result_lines.append(f'    {skill}: allow')
            
            continue  # Skip adding the original tools line
        
        # Transform name for skills
        if file_type == 'skill' and line.startswith('name:'):
            name_match = re.match(r'^name:\s*(.+)$', line)
            if name_match:
                old_name = name_match.group(1).strip()
                line = f'name: {plugin_name}-{old_name}'
        
        # Transform name for agents
        if file_type == 'agent' and line.startswith('name:'):
            name_match = re.match(r'^name:\s*(.+)$', line)
            if name_match:
                old_name = name_match.group(1).strip()
                line = f'name: {plugin_name}.{old_name}'
        
        # Apply content transforms to all lines (handles /plugin:cmd in description, etc.)
        line = transform_content(line)
        
        result_lines.append(line)
    
    # If we have argument-hint but no description line, add description
    if file_type == 'command' and argument_hint and description_line_idx is None:
        result_lines.insert(0, f'description: "Args: {argument_hint}"')
    
    # Add mode: subagent for agents if not present
    if file_type == 'agent':
        has_mode = any(line.startswith('mode:') for line in result_lines)
        if not has_mode:
            result_lines.append('mode: subagent')
    
    return '\n'.join(result_lines) + '\n'


def transform_yaml_strings(obj):
    """Recursively apply content transforms to string values in YAML objects.
    
    This ensures /plugin:cmd -> /plugin.cmd and other transforms
    are applied to description fields, etc.
    """
    if isinstance(obj, str):
        return transform_content(obj)
    elif isinstance(obj, dict):
        return {k: transform_yaml_strings(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [transform_yaml_strings(item) for item in obj]
    else:
        return obj


def transform_frontmatter(frontmatter_str, plugin_name, file_type):
    """Transform Claude Code frontmatter to OpenCode format.
    
    Args:
        frontmatter_str: Raw YAML frontmatter string
        plugin_name: Name of the plugin (e.g., 'dut', 'bugz')
        file_type: One of 'command', 'skill', 'agent'
    
    Returns:
        Transformed frontmatter as YAML string
    """
    # Pre-process to fix malformed frontmatter (e.g., lines after description
    # that aren't properly formatted as YAML multi-line strings)
    frontmatter_str = fix_malformed_frontmatter(frontmatter_str)
    
    try:
        fm = yaml.safe_load(frontmatter_str) or {}
    except yaml.YAMLError:
        # Fall back to regex-based transformation
        return transform_frontmatter_regex(frontmatter_str, plugin_name, file_type)
    
    # === COMMAND-SPECIFIC TRANSFORMS ===
    if file_type == 'command':
        # Append argument-hint to description
        if 'argument-hint' in fm:
            hint = fm.pop('argument-hint')
            desc = fm.get('description', '')
            if desc:
                # Strip trailing punctuation to avoid double periods
                desc = desc.rstrip('.!? ')
                fm['description'] = f"{desc}. Args: {hint}"
            else:
                fm['description'] = f"Args: {hint}"
        
        # Remove allowed-tools (no OpenCode equivalent)
        fm.pop('allowed-tools', None)
    
    # === AGENT-SPECIFIC TRANSFORMS ===
    if file_type == 'agent':
        # Transform name: add plugin prefix with dot
        if 'name' in fm:
            fm['name'] = f"{plugin_name}.{fm['name']}"
        
        # Add mode: subagent
        if 'mode' not in fm:
            fm['mode'] = 'subagent'
        
        # Remove color (not supported)
        fm.pop('color', None)
        
        # Transform tools field
        if 'tools' in fm and isinstance(fm['tools'], str):
            tools_enabled, skill_refs = parse_tools_line(fm['tools'])
            
            # Build new tools dict
            new_tools = {}
            for tool in ['bash', 'read', 'grep', 'glob', 'list', 'webfetch']:
                if tool in tools_enabled:
                    new_tools[tool] = True
            
            # Disable edit tools if not enabled
            if 'edit' not in tools_enabled:
                new_tools['edit'] = False
            
            fm['tools'] = new_tools
            
            # Add skill permissions if any
            if skill_refs:
                fm['permission'] = {
                    'skill': {skill: 'allow' for skill in skill_refs}
                }
    
    # === SKILL-SPECIFIC TRANSFORMS ===
    if file_type == 'skill':
        # Transform name: add plugin prefix with hyphen
        if 'name' in fm:
            fm['name'] = f"{plugin_name}-{fm['name']}"
    
    # === COMMON TRANSFORMS ===
    
    # Transform model names
    if 'model' in fm and fm['model'] in MODEL_MAP:
        fm['model'] = MODEL_MAP[fm['model']]
    
    # Apply content transforms to string values (description, etc.)
    # This handles /plugin:cmd -> /plugin.cmd in description fields
    fm = transform_yaml_strings(fm)
    
    # Return as YAML with safe quoting for special characters
    return yaml_safe_dump(fm)


def transform_content(content):
    """Transform content body (after frontmatter).
    
    Transforms:
    - $ARGS -> $ARGUMENTS
    - /plugin:cmd -> /plugin.cmd
    - Skill(plugin:skill) -> plugin-skill skill
    - `plugin:skill` -> `plugin-skill` (backtick-quoted references)
    """
    # $ARGS -> $ARGUMENTS
    content = content.replace('$ARGS', '$ARGUMENTS')
    
    # /plugin:cmd -> /plugin.cmd
    # Note: hyphen must be at end of character class to be treated literally
    content = re.sub(r'/([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)', r'/\1.\2', content)
    
    # Skill(plugin:skill) -> plugin-skill skill
    content = re.sub(
        r'Skill\(([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)\)',
        r'\1-\2 skill',
        content,
        flags=re.IGNORECASE
    )
    
    # Backtick-quoted skill references: `plugin:skill` -> `plugin-skill`
    # This handles references like `mut:commit-message` skill or just `dut:ssh`
    content = re.sub(
        r'`([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)`',
        r'`\1-\2`',
        content
    )
    
    return content


def process_file(filepath, plugin_name, file_type):
    """Process a single markdown file.
    
    Args:
        filepath: Path to the markdown file
        plugin_name: Name of the plugin
        file_type: One of 'command', 'skill', 'agent'
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Split frontmatter from content
    # Format: ---\nfrontmatter\n---\ncontent
    # Only treat as having frontmatter if file starts with ---
    if content.startswith('---'):
        parts = content.split('---', 2)
        if len(parts) >= 3:
            # Transform both frontmatter and content
            frontmatter = transform_frontmatter(parts[1].strip(), plugin_name, file_type)
            body = transform_content(parts[2])
            new_content = f"---\n{frontmatter}---{body}"
        else:
            # Malformed frontmatter, just transform content
            new_content = transform_content(content)
    else:
        # No frontmatter, just transform content
        new_content = transform_content(content)
    
    # Write back
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)


def get_skill_name_from_frontmatter(skill_dir):
    """Extract the 'name' field from a skill's SKILL.md frontmatter.
    
    Returns the name if found, otherwise None.
    """
    skill_file = os.path.join(skill_dir, 'SKILL.md')
    if not os.path.isfile(skill_file):
        return None
    
    try:
        with open(skill_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Parse frontmatter
        if not content.startswith('---'):
            return None
        
        parts = content.split('---', 2)
        if len(parts) < 3:
            return None
        
        # Try YAML parsing first
        try:
            fm = yaml.safe_load(parts[1].strip()) or {}
            return fm.get('name')
        except yaml.YAMLError:
            # Fall back to regex
            match = re.search(r'^name:\s*(.+)$', parts[1], re.MULTILINE)
            if match:
                return match.group(1).strip()
    except Exception:
        pass
    
    return None


def rename_skill_directories(plugin_dir, plugin_name):
    """Rename skill directories to match the name in SKILL.md frontmatter.
    
    This ensures the directory name matches what OpenCode expects based on the
    skill's 'name' field. After transformation, the name field will be prefixed
    with the plugin name, so we use that transformed name for the directory.
    
    Example: If SKILL.md has name: triage-tools-job-triager (after transform),
    the directory should be named triage-tools-job-triager, not the original
    directory name.
    """
    skills_dir = os.path.join(plugin_dir, 'skills')
    if not os.path.isdir(skills_dir):
        return
    
    for skill_dirname in os.listdir(skills_dir):
        skill_path = os.path.join(skills_dir, skill_dirname)
        if not os.path.isdir(skill_path):
            continue
        
        # Get the name from the frontmatter (already transformed at this point)
        frontmatter_name = get_skill_name_from_frontmatter(skill_path)
        
        if frontmatter_name and frontmatter_name != skill_dirname:
            # Rename directory to match frontmatter name
            new_path = os.path.join(skills_dir, frontmatter_name)
            if not os.path.exists(new_path):
                shutil.move(skill_path, new_path)
        elif not frontmatter_name:
            # Fallback: prefix with plugin name if no frontmatter name found
            if not skill_dirname.startswith(f"{plugin_name}-"):
                new_name = f"{plugin_name}-{skill_dirname}"
                new_path = os.path.join(skills_dir, new_name)
                if not os.path.exists(new_path):
                    shutil.move(skill_path, new_path)


def process_markdown_files_recursive(directory, plugin_name, file_type):
    """Recursively process all .md files in a directory.
    
    Args:
        directory: Directory to search
        plugin_name: Name of the plugin
        file_type: Type to use for frontmatter transformation
    """
    for root, dirs, files in os.walk(directory):
        for filename in files:
            if filename.endswith('.md'):
                filepath = os.path.join(root, filename)
                process_file(filepath, plugin_name, file_type)


def process_plugin(plugin_dir, plugin_name):
    """Process all files in a plugin directory."""
    
    # Process commands
    commands_dir = os.path.join(plugin_dir, 'commands')
    if os.path.isdir(commands_dir):
        for filename in os.listdir(commands_dir):
            if filename.endswith('.md'):
                filepath = os.path.join(commands_dir, filename)
                process_file(filepath, plugin_name, 'command')
    
    # Process agents
    agents_dir = os.path.join(plugin_dir, 'agents')
    if os.path.isdir(agents_dir):
        for filename in os.listdir(agents_dir):
            if filename.endswith('.md'):
                filepath = os.path.join(agents_dir, filename)
                process_file(filepath, plugin_name, 'agent')
    
    # Process skills - SKILL.md gets 'skill' type, all other .md files get 'other'
    skills_dir = os.path.join(plugin_dir, 'skills')
    if os.path.isdir(skills_dir):
        for skill_name in os.listdir(skills_dir):
            skill_path = os.path.join(skills_dir, skill_name)
            if os.path.isdir(skill_path):
                # Process SKILL.md with 'skill' type for frontmatter transforms
                skill_file = os.path.join(skill_path, 'SKILL.md')
                if os.path.isfile(skill_file):
                    process_file(skill_file, plugin_name, 'skill')
                
                # Process all other .md files recursively (reference/, etc.)
                for root, dirs, files in os.walk(skill_path):
                    for filename in files:
                        if filename.endswith('.md') and filename != 'SKILL.md':
                            filepath = os.path.join(root, filename)
                            # Use 'other' type - only content transforms, no frontmatter changes
                            process_file(filepath, plugin_name, 'other')
    
    # Process README.md and CLAUDE.md at plugin root
    for filename in ['README.md', 'CLAUDE.md']:
        filepath = os.path.join(plugin_dir, filename)
        if os.path.isfile(filepath):
            process_file(filepath, plugin_name, 'other')
    
    # Process docs/ directory if present
    docs_dir = os.path.join(plugin_dir, 'docs')
    if os.path.isdir(docs_dir):
        process_markdown_files_recursive(docs_dir, plugin_name, 'other')
    
    # Rename skill directories to include plugin prefix
    rename_skill_directories(plugin_dir, plugin_name)


def main():
    if len(sys.argv) < 2:
        print("Usage: transform-plugins.py <plugins-directory>", file=sys.stderr)
        sys.exit(1)
    
    root = sys.argv[1]
    
    # Process each plugin directory
    for plugin_name in os.listdir(root):
        plugin_dir = os.path.join(root, plugin_name)
        if os.path.isdir(plugin_dir):
            process_plugin(plugin_dir, plugin_name)


if __name__ == '__main__':
    main()
