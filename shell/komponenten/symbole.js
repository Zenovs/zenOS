.pragma library

// Symbole aus Entwurf 2: Pfad in SVG-Syntax (24er ViewBox) und Standard-Strichbreite.
// Kreise und Rechtecke sind in Pfade umgerechnet.
var daten = {
    "suche": { d: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0zM20 20l-3.5-3.5", strich: 1.8 },
    "glocke": { d: "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0", strich: 1.7 },
    "glocke-aus": { d: "M8.7 3A6 6 0 0 1 18 8c0 2.4.4 4.3.9 5.7M17 17H3s3-2 3-9c0-.4 0-.8.1-1.2M10.3 21a1.94 1.94 0 0 0 3.4 0M2 2l20 20", strich: 1.7 },
    "mond": { d: "M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z", strich: 1.7 },
    "sonne": { d: "M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4", strich: 1.7 },
    "wlan": { d: "M5 12.6a11 11 0 0 1 14 0M1.5 9a16 16 0 0 1 21 0M8.5 16.1a6 6 0 0 1 7 0M12 20h.01", strich: 1.8 },
    // Signalstufen: «wlan» ohne den äusseren (2) bzw. ohne die beiden äusseren Bögen (1). Die Leiste legt sie über
    // ein blasses «wlan», damit die fehlenden Bögen angedeutet bleiben (leiste/WlanSymbol.qml).
    "wlan-2": { d: "M5 12.6a11 11 0 0 1 14 0M8.5 16.1a6 6 0 0 1 7 0M12 20h.01", strich: 1.8 },
    "wlan-1": { d: "M8.5 16.1a6 6 0 0 1 7 0M12 20h.01", strich: 1.8 },
    // Bögen wie «wlan», hinter dem Strich unterbrochen
    "wlan-aus": { d: "M1.5 9a16 16 0 0 1 4.67-2.83M10.78 5.12A16 16 0 0 1 22.5 9M5 12.6a11 11 0 0 1 5.23-2.37M16.89 11.23A11 11 0 0 1 19 12.6M8.5 16.1a6 6 0 0 1 7 0M12 20h.01M2 2l20 20", strich: 1.8 },
    // Netzwerkbuchse (Ethernet)
    "kabel": { d: "M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1 -2 2h-2.5l-3 3h-5l-3 -3h-2.5a2 2 0 0 1 -2 -2v-9a2 2 0 0 1 2 -2zM8 8v2M12 8v2M16 8v2", strich: 1.8 },
    "ton": { d: "M11 5L6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7", strich: 1.8 },
    "ton-aus": { d: "M11 5L6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6", strich: 1.8 },
    "schloss": { d: "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM8 11V7a4 4 0 0 1 8 0v4", strich: 1.8 },
    "schloss-offen": { d: "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM8 11V7a4 4 0 0 1 7.8-1.3", strich: 1.8 },
    "raster4": { d: "M4.5 3h4.5a1.5 1.5 0 0 1 1.5 1.5v4.5a1.5 1.5 0 0 1 -1.5 1.5h-4.5a1.5 1.5 0 0 1 -1.5 -1.5v-4.5a1.5 1.5 0 0 1 1.5 -1.5zM15 3h4.5a1.5 1.5 0 0 1 1.5 1.5v4.5a1.5 1.5 0 0 1 -1.5 1.5h-4.5a1.5 1.5 0 0 1 -1.5 -1.5v-4.5a1.5 1.5 0 0 1 1.5 -1.5zM4.5 13.5h4.5a1.5 1.5 0 0 1 1.5 1.5v4.5a1.5 1.5 0 0 1 -1.5 1.5h-4.5a1.5 1.5 0 0 1 -1.5 -1.5v-4.5a1.5 1.5 0 0 1 1.5 -1.5zM15 13.5h4.5a1.5 1.5 0 0 1 1.5 1.5v4.5a1.5 1.5 0 0 1 -1.5 1.5h-4.5a1.5 1.5 0 0 1 -1.5 -1.5v-4.5a1.5 1.5 0 0 1 1.5 -1.5z", strich: 1.8 },
    "raster-voll": { d: "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2z", strich: 1.8 },
    "pfeil-runter": { d: "M6 9l6 6 6-6", strich: 2.0 },
    "plus": { d: "M12 5v14M5 12h14", strich: 1.8 },
    "x": { d: "M6 6l12 12M18 6L6 18", strich: 2.0 },
    "play": { d: "M7 4v16l13-8z", strich: 0, gefuellt: true },
    "pipette": { d: "M2 22l1-1h3l9-9M3 21v-3l9-9M15 6l3.4-3.4a2.1 2.1 0 1 1 3 3L18 9l.4.4a2.1 2.1 0 1 1-3 3l-3.8-3.8a2.1 2.1 0 1 1 3-3z", strich: 1.7 },
    "bildschirmfoto": { d: "M6 2v14a2 2 0 0 0 2 2h14M18 22V8a2 2 0 0 0-2-2H2", strich: 1.7 },
    "messen": { d: "M3 17L17 3l4 4L7 21zM7 13l2 2M10 10l2 2M13 7l2 2", strich: 1.7 },
    "kreis-ziel": { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0zM9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", strich: 1.8 },
    "aufnahme": { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0zM8.5 12a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0 -7 0z", strich: 1.7 },
    "monitor": { d: "M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2zM8 21h8M12 17v4", strich: 2.0 },
    "warnung": { d: "M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01", strich: 1.8 },
    "info": { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0zM12 16v-4.5M12 8h.01", strich: 1.8 },
    "haken": { d: "M20 6L9 17l-5-5", strich: 1.8 },
    "aufgabe": { d: "M6 3h12a3 3 0 0 1 3 3v12a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-12a3 3 0 0 1 3 -3zM8 12l3 3 5-6", strich: 1.7 },
    "code": { d: "M16 18l6-6-6-6M8 6l-6 6 6 6", strich: 1.7 },
    "terminal": { d: "M4 17l6-6-6-6M12 19h8", strich: 1.8 },
    "zahnrad": { d: "M10.604 5.141L10.747 2.482L13.253 2.482L13.396 5.141A7 7 0 0 1 15.864 6.163L17.844 4.384L19.616 6.156L17.837 8.136A7 7 0 0 1 18.859 10.604L21.518 10.747L21.518 13.253L18.859 13.396A7 7 0 0 1 17.837 15.864L19.616 17.844L17.844 19.616L15.864 17.837A7 7 0 0 1 13.396 18.859L13.253 21.518L10.747 21.518L10.604 18.859A7 7 0 0 1 8.136 17.837L6.156 19.616L4.384 17.844L6.163 15.864A7 7 0 0 1 5.141 13.396L2.482 13.253L2.482 10.747L5.141 10.604A7 7 0 0 1 6.163 8.136L4.384 6.156L6.156 4.384L8.136 6.163A7 7 0 0 1 10.604 5.141zM9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", strich: 1.7 },
    "wolke": { d: "M17.5 19H9a7 7 0 1 1 6.7-9h1.8a4.5 4.5 0 1 1 0 9z", strich: 1.7 },
    "text-aus-bild": { d: "M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2M8 8h8M12 8v8", strich: 1.7 },
    "qr-code": { d: "M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1zM15 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1zM4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1zM14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h4v-3", strich: 1.7 },
    "zwischenablage": { d: "M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1 -1 1h-6a1 1 0 0 1 -1 -1v-2a1 1 0 0 1 1 -1zM16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2", strich: 1.7 },
    "thermometer": { d: "M14 4v10.54a4 4 0 1 1 -4 0V4a2 2 0 0 1 4 0z", strich: 1.8 },
    // Akku waagrecht (Körper 16 × 10, Pol rechts), Füllstand als Striche: leer ≤ 10 %, wenig, halb, voll
    "akku-leer": { d: "M4 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM21 10.5v3", strich: 1.8 },
    "akku-wenig": { d: "M4 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM21 10.5v3M6 10.5v3", strich: 1.8 },
    "akku-halb": { d: "M4 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM21 10.5v3M6 10.5v3M10 10.5v3", strich: 1.8 },
    "akku-voll": { d: "M4 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2zM21 10.5v3M6 10.5v3M10 10.5v3M14 10.5v3", strich: 1.8 },
    // Akku mit Ladeblitz: der Körper ist oben und unten dort offen, wo der Blitz hindurchgeht
    "akku-laedt": { d: "M8.5 7H4a2 2 0 0 0 -2 2v6a2 2 0 0 0 2 2h2.5M13.5 7h2.5a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-4.5M21 10.5v3M11.5 5.5l-3.5 6.5h4l-3.5 6.5", strich: 1.8 },
    // Lüfter: drei geschwungene Blätter um eine Nabe
    "luefter": { d: "M11.1 10C9.4 6.8 10.6 2.4 13.6 2.6C16.6 2.8 16.4 7 13.9 10.6M14.18 12.22C17.8 12.35 21.01 15.59 19.34 18.09C17.67 20.58 14.13 18.31 12.26 14.35M10.72 13.78C8.8 16.85 4.39 18.01 3.06 15.31C1.73 12.62 5.47 10.69 9.84 11.05M10.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0z", strich: 1.7 },
    "ausschalten": { d: "M12 3v9M18.4 6.6a9 9 0 1 1-12.8 0", strich: 1.8 },
    "neustart": { d: "M3 12a9 9 0 1 0 2.64-6.36L3 8.3M3 3v5.3h5.3", strich: 1.8 },
    "abmelden": { d: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9", strich: 1.8 },
    "datei": { d: "M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9zM14 3v6h6", strich: 1.7 },
    "ordner": { d: "M5 4h3.9a2 2 0 0 1 1.66.9l.88 1.3a2 2 0 0 0 1.66.9H19a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z", strich: 1.7 }
};
