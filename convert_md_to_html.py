import re
import markdown

with open("TECHNICAL_GUIDANCE.md", "r", encoding="utf-8") as f:
    md_content = f.read()

# Custom preprocessing for callouts and mermaid
def replace_callouts(text):
    lines = text.split("\n")
    new_lines = []
    in_callout = False
    callout_type = ""
    callout_content = []

    for line in lines:
        note_match = re.match(r"^>\s*\[!NOTE\]\s*(.*)", line, re.IGNORECASE)
        imp_match = re.match(r"^>\s*\[!IMPORTANT\]\s*(.*)", line, re.IGNORECASE)

        if note_match or imp_match:
            if in_callout:
                new_lines.append(f'<div class="callout callout-{callout_type}">{" ".join(callout_content)}</div>')
                callout_content = []
            in_callout = True
            if note_match:
                callout_type = "note"
                first_text = note_match.group(1)
            else:
                callout_type = "important"
                first_text = imp_match.group(1)
            if first_text:
                callout_content.append(first_text)
        elif in_callout and line.startswith(">"):
            content = line.lstrip("> ").strip()
            callout_content.append(content)
        else:
            if in_callout:
                new_lines.append(f'<div class="callout callout-{callout_type}">{" ".join(callout_content)}</div>')
                in_callout = False
                callout_content = []
                callout_type = ""
            new_lines.append(line)

    if in_callout:
        new_lines.append(f'<div class="callout callout-{callout_type}">{" ".join(callout_content)}</div>')

    return "\n".join(new_lines)

processed_md = replace_callouts(md_content)

def replace_mermaid(match):
    code = match.group(1).strip()
    return f'<div class="mermaid">\n{code}\n</div>'

processed_md = re.sub(r'```mermaid\s*\n(.*?)```', replace_mermaid, processed_md, flags=re.DOTALL)

html_body = markdown.markdown(
    processed_md,
    extensions=['tables', 'fenced_code', 'toc', 'nl2br']
)

html_body = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', html_body)

full_html = f"""<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Panduan Teknis NutriXense</title>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <style>
        @page {{
            size: A4;
            margin: 18mm 15mm 18mm 15mm;
        }}
        * {{
            box-sizing: border-box;
        }}
        body {{
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            color: #1e293b;
            line-height: 1.6;
            font-size: 12.5px;
            background-color: #ffffff;
            margin: 0;
            padding: 0;
        }}
        
        .doc-header {{
            border-bottom: 3px solid #059669;
            padding-bottom: 12px;
            margin-bottom: 20px;
        }}
        
        h1 {{
            color: #064e3b;
            font-size: 22px;
            font-weight: 800;
            margin-top: 0;
            margin-bottom: 6px;
            line-height: 1.3;
        }}
        
        h2 {{
            color: #065f46;
            font-size: 15px;
            font-weight: 700;
            border-bottom: 1.5px solid #a7f3d0;
            padding-bottom: 5px;
            margin-top: 24px;
            margin-bottom: 12px;
            page-break-after: avoid;
        }}
        
        h3 {{
            color: #0f766e;
            font-size: 13.5px;
            font-weight: 700;
            margin-top: 18px;
            margin-bottom: 8px;
            page-break-after: avoid;
        }}
        
        p {{
            margin-top: 0;
            margin-bottom: 10px;
            text-align: justify;
        }}
        
        ul, ol {{
            margin-top: 0;
            margin-bottom: 12px;
            padding-left: 20px;
        }}
        
        li {{
            margin-bottom: 4px;
        }}
        
        /* Tables */
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 14px 0;
            font-size: 11px;
            page-break-inside: avoid;
        }}
        
        th, td {{
            padding: 6px 9px;
            border: 1px solid #cbd5e1;
            text-align: left;
            vertical-align: top;
        }}
        
        th {{
            background-color: #064e3b;
            color: #ffffff;
            font-weight: 600;
        }}
        
        tr:nth-child(even) {{
            background-color: #f8fafc;
        }}
        
        /* Callout Boxes */
        .callout {{
            padding: 10px 14px;
            margin: 14px 0;
            border-left: 4px solid;
            border-radius: 4px;
            font-size: 11.5px;
            page-break-inside: avoid;
        }}
        
        .callout-note {{
            background-color: #f0fdf4;
            border-color: #10b981;
            color: #064e3b;
        }}
        
        .callout-important {{
            background-color: #fffbe6;
            border-color: #f59e0b;
            color: #78350f;
        }}
        
        /* Code Blocks */
        pre {{
            background-color: #0f172a;
            color: #f8fafc;
            padding: 10px 12px;
            border-radius: 6px;
            font-family: 'Consolas', 'Cascadia Code', Monaco, monospace;
            font-size: 10px;
            line-height: 1.4;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-all;
            margin: 12px 0;
            page-break-inside: avoid;
        }}
        
        code {{
            font-family: 'Consolas', 'Cascadia Code', Monaco, monospace;
            background-color: #f1f5f9;
            color: #0f172a;
            padding: 2px 4px;
            border-radius: 3px;
            font-size: 11px;
        }}
        
        pre code {{
            background: transparent;
            color: inherit;
            padding: 0;
        }}
        
        /* Mermaid Diagram */
        .mermaid {{
            display: flex;
            justify-content: center;
            align-items: center;
            background-color: #fafafa;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            padding: 14px;
            margin: 16px 0;
            page-break-inside: avoid;
        }}
        
        hr {{
            border: 0;
            height: 1px;
            background: #cbd5e1;
            margin: 20px 0;
        }}
    </style>
</head>
<body>
    <div class="content">
        {html_body}
    </div>
    <script>
        mermaid.initialize({{
            startOnLoad: true,
            theme: 'forest',
            securityLevel: 'loose',
            flowchart: {{
                useMaxWidth: true,
                htmlLabels: true
            }}
        }});
    </script>
</body>
</html>
"""

with open("TECHNICAL_GUIDANCE.html", "w", encoding="utf-8") as f:
    f.write(full_html)

print("TECHNICAL_GUIDANCE.html generated successfully!")
