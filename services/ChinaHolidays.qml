pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property string subscriptionUrl: "https://holiday.ailcc.com/api/holiday/ics"
    property var subscribedEvents: ({})
    property bool refreshing

    // Official annual schedules:
    // 2026: https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm
    // 2025: https://www.gov.cn/zhengce/zhengceku/202411/content_6986383.htm
    readonly property var schedules: ({
        "2025": {
            holidays: [
                ["2025-01-01", "2025-01-01", "元旦"],
                ["2025-01-28", "2025-02-04", "春节"],
                ["2025-04-04", "2025-04-06", "清明"],
                ["2025-05-01", "2025-05-05", "劳动节"],
                ["2025-05-31", "2025-06-02", "端午"],
                ["2025-10-01", "2025-10-08", "国庆/中秋"]
            ],
            workdays: ["2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11"]
        },
        "2026": {
            holidays: [
                ["2026-01-01", "2026-01-03", "元旦"],
                ["2026-02-15", "2026-02-23", "春节"],
                ["2026-04-04", "2026-04-06", "清明"],
                ["2026-05-01", "2026-05-05", "劳动节"],
                ["2026-06-19", "2026-06-21", "端午"],
                ["2026-09-25", "2026-09-27", "中秋"],
                ["2026-10-01", "2026-10-07", "国庆节"]
            ],
            workdays: ["2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10"]
        }
    })

    function eventInfo(summary: string): var {
        const workday = /[（(]班[）)]/.test(summary);
        const holiday = /[（(]休[）)]/.test(summary);
        const name = summary.replace(/[（(][休班][）)]/g, "").trim();
        return {
            kind: workday ? "workday" : holiday ? "holiday" : "event",
            label: workday ? "班" : holiday ? "休" : name,
            name: summary
        };
    }

    function mergeEvent(entries: var, dateKey: string, event: var): void {
        const old = entries[dateKey];
        if (!old) {
            entries[dateKey] = event;
            return;
        }

        const priority = {
            event: 0,
            holiday: 1,
            workday: 2
        };
        const primary = priority[event.kind] > priority[old.kind] ? event : old;
        const names = old.name === event.name ? old.name : `${old.name}、${event.name}`;
        entries[dateKey] = {
            kind: primary.kind,
            label: primary.label,
            name: names
        };
    }

    function parseCalendar(text: string): bool {
        if (!text.includes("BEGIN:VCALENDAR"))
            return false;

        // RFC 5545 permits a physical line to continue on the next indented line.
        const unfolded = text.replace(/\r\n[ \t]/g, "").replace(/\r/g, "");
        const entries = {};
        const events = unfolded.split("BEGIN:VEVENT");
        let count = 0;

        for (let i = 1; i < events.length; i++) {
            const block = events[i].split("END:VEVENT")[0];
            const startMatch = block.match(/^DTSTART(?:;[^:]*)?:(\d{8})/m);
            const endMatch = block.match(/^DTEND(?:;[^:]*)?:(\d{8})/m);
            const summaryMatch = block.match(/^SUMMARY:(.*)$/m);
            if (!startMatch || !summaryMatch)
                continue;

            const summary = summaryMatch[1].replace(/\\([,;\\])/g, "$1").trim();
            const start = new Date(Date.UTC(Number(startMatch[1].slice(0, 4)), Number(startMatch[1].slice(4, 6)) - 1, Number(startMatch[1].slice(6, 8))));
            const endValue = endMatch ? endMatch[1] : startMatch[1];
            let end = new Date(Date.UTC(Number(endValue.slice(0, 4)), Number(endValue.slice(4, 6)) - 1, Number(endValue.slice(6, 8))));
            if (end <= start)
                end = new Date(start.getTime() + 86400000);

            const parsed = eventInfo(summary);
            for (let cursor = start.getTime(); cursor < end.getTime(); cursor += 86400000) {
                const date = new Date(cursor);
                const dateKey = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
                mergeEvent(entries, dateKey, parsed);
            }
            count++;
        }

        if (count === 0)
            return false;
        subscribedEvents = entries;
        return true;
    }

    function refresh(): void {
        if (refreshing)
            return;
        refreshing = true;
        download.command = ["curl", "-fsSL", "--max-time", "15", "-A", "villode-caelestia/1.0", subscriptionUrl];
        download.running = true;
    }

    function key(date: date): string {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${year}-${month}-${day}`;
    }

    function info(date: date): var {
        const dateKey = key(date);
        if (subscribedEvents[dateKey])
            return subscribedEvents[dateKey];

        const schedule = schedules[String(date.getFullYear())];
        if (!schedule)
            return null;

        if (schedule.workdays.includes(dateKey)) {
            return {
                kind: "workday",
                label: "班",
                name: "调休上班"
            };
        }

        for (const range of schedule.holidays) {
            if (dateKey >= range[0] && dateKey <= range[1]) {
                return {
                    kind: "holiday",
                    label: "休",
                    name: range[2]
                };
            }
        }
        return null;
    }

    FileView {
        id: cacheFile

        path: `${Paths.cache}/china-holidays.ics`
        printErrors: false
        atomicWrites: true
        onLoaded: root.parseCalendar(text())
    }

    Process {
        id: download

        stdout: StdioCollector {
            id: downloadOutput
        }
        onExited: code => {
            root.refreshing = false;
            if (code === 0 && root.parseCalendar(downloadOutput.text))
                cacheFile.setText(downloadOutput.text);
        }
    }

    Timer {
        interval: 21600000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
