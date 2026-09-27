.pragma library

// Deutsche Datums- und Zeitangaben für Leiste und «Heute», unabhängig von der System-Locale.

var WEEKDAYS = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
var WEEKDAYS_SHORT = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
var MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
var MONTHS_SHORT = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// Date, Zahl (ms) oder Text → Date, sonst null
function validDate(value) {
    if (value === null || value === undefined || value === "")
        return null;
    var d = value instanceof Date ? value : new Date(value);
    return isNaN(d.getTime()) ? null : d;
}

// «08:12» (24 h)
function time(date) {
    var d = validDate(date);
    return d ? pad2(d.getHours()) + ":" + pad2(d.getMinutes()) : "";
}

// «Mo 28. Sep»
function shortDate(date) {
    var d = validDate(date);
    return d ? WEEKDAYS_SHORT[d.getDay()] + " " + d.getDate() + ". " + MONTHS_SHORT[d.getMonth()] : "";
}

// «Montag · September»
function dayMonth(date) {
    var d = validDate(date);
    return d ? WEEKDAYS[d.getDay()] + " · " + MONTHS[d.getMonth()] : "";
}

// Gruss nach Uhrzeit: Morgen bis 11 Uhr, Tag bis 18 Uhr, danach Abend
function greeting(hour) {
    if (hour >= 5 && hour < 11)
        return "Guten Morgen";
    if (hour >= 11 && hour < 18)
        return "Guten Tag";
    return "Guten Abend";
}

// «38 Min.», «1 Std.», «1 Std. 20 Min.»
function duration(minutes) {
    var m = Math.max(0, Math.round(Number(minutes) || 0));
    if (m < 60)
        return m + " Min.";
    var h = Math.floor(m / 60);
    var rest = m % 60;
    return rest === 0 ? h + " Std." : h + " Std. " + rest + " Min.";
}

// Nächster Zeitpunkt nach «now», der ein Vielfaches von «interval» Minuten ab Mitternacht ist
function nextSlot(now, interval) {
    var d = validDate(now);
    var n = Math.round(Number(interval));
    if (!d || !(n > 0))
        return null;
    // Wanduhr-Minuten statt Millisekunden, damit die Umstellung auf Sommerzeit nichts verschiebt
    var passed = d.getHours() * 60 + d.getMinutes();
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, (Math.floor(passed / n) + 1) * n);
}
