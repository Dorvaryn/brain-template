#!/bin/bash
# gemini-statusline-calendar.sh — Extremely fast calendar scraper

BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"

NEXT_EVENT=$(python3 - <<'PYEOF' 2>/dev/null || echo "None"
import os, sys, glob, datetime, re

brain_dir = os.path.expanduser("~/brain")
files = glob.glob(os.path.join(brain_dir, "raw/*-calendar/*.md"))
if not files:
    sys.exit(1)

# Sort files by modification time descending
files.sort(key=os.path.getmtime, reverse=True)

now = datetime.datetime.now(datetime.timezone.utc)
next_event = None
min_delta = datetime.timedelta(days=365)

# RegEx to match all variations of calendar headings
regex = re.compile(
    r'## (?:Calendar Event|Calendar: Calendar|Calendar Today|Calendar|\[Calendar\]|\[Personal\])?\s*[-—:]?\s*(.*?)\nArea: (.*?)\nDate/Time: (.*?)\n'
)

for filepath in files:
    with open(filepath) as f:
        content = f.read()
    
    matches = regex.finditer(content)
    for m in matches:
        title, area, dt_str = m.groups()
        dt_str = dt_str.strip()
        
        # Extract the start date/time part from range or string
        date_match = re.match(
            r'^(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+)?'
            r'(\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?)?)',
            dt_str,
            re.IGNORECASE
        )
        if not date_match:
            continue
            
        start_dt_str = date_match.group(1).strip()
        
        dt = None
        try:
            if 'T' in start_dt_str:
                if start_dt_str.endswith('Z'):
                    dt = datetime.datetime.fromisoformat(start_dt_str.replace('Z', '+00:00'))
                else:
                    dt = datetime.datetime.fromisoformat(start_dt_str)
            else:
                for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d"):
                    try:
                        dt = datetime.datetime.strptime(start_dt_str, fmt).replace(tzinfo=datetime.timezone.utc)
                        break
                    except ValueError:
                        continue
        except Exception:
            continue
            
        if dt is None:
            continue
            
        dt_utc = dt.astimezone(datetime.timezone.utc)
        if dt_utc > now:
            delta = dt_utc - now
            if delta < min_delta:
                min_delta = delta
                local_dt = dt.astimezone() # convert to system local timezone
                time_str = local_dt.strftime("%H:%M")
                if local_dt.date() != datetime.date.today():
                    time_str = local_dt.strftime("%a %H:%M")
                
                # Truncate title only, keeping the time string fully visible
                display_title = title.strip()
                if len(display_title) > 20:
                    display_title = display_title[:17] + "..."
                next_event = f"{display_title} ({time_str})"

if next_event:
    print(next_event)
else:
    print("None")
PYEOF
)

if [[ "$NEXT_EVENT" != "None" ]]; then
  echo "$NEXT_EVENT"
else
  echo ""
fi
