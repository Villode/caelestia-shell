pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.modules.dashboard.dash as Dash

Item {
    id: root

    implicitWidth: 340
    implicitHeight: calendar.implicitHeight

    DashboardState {
        id: calendarState

        reloadableId: "barCalendarState"
    }

    Dash.Calendar {
        id: calendar

        dashState: calendarState
    }
}
