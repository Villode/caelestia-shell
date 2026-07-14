pragma Singleton

import QtQuick
import Quickshell

Singleton {
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

    function key(date: date): string {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${year}-${month}-${day}`;
    }

    function info(date: date): var {
        const dateKey = key(date);
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
}
