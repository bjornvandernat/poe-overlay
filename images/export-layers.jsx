// Exports every top-level layer / group of the active document as its own PNG-24 (Save for Web),
// using the layer name as the file name. Run with File > Scripts > Browse...
#target photoshop
var doc = app.activeDocument;
var folder = Folder.selectDialog("Export layers to...");
if (folder) {
    var layers = doc.layers, wasVisible = [], done = [], i, j;
    for (i = 0; i < layers.length; i++) wasVisible.push(layers[i].visible);

    var opts = new ExportOptionsSaveForWeb();
    opts.format = SaveDocumentType.PNG;
    opts.PNG8 = false;            // PNG-24
    opts.transparency = true;
    opts.interlaced = false;

    for (i = 0; i < layers.length; i++) {
        for (j = 0; j < layers.length; j++) layers[j].visible = (j == i);   // only this layer on
        // not called "name": that is a built-in global in Photoshop scripting (the application name)
        var layerName = layers[i].name.replace(/\.png$/i, "").replace(/[\\\/:*?"<>|]/g, "_");
        var file = new File(folder.fullName + "/" + layerName + ".png");
        doc.exportDocument(file, ExportType.SAVEFORWEB, opts);
        done.push(file.fsName);
    }
    for (i = 0; i < layers.length; i++) layers[i].visible = wasVisible[i];   // put visibility back
    alert("Exported " + done.length + " layers:\n" + done.join("\n"));
}
