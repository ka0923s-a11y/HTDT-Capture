# Sample equipment catalog

`equipment-catalog-snapshot.json` is a valid
`htdt.equipment.catalog-snapshot` document (authority version
`o100c-equipment-definition-1`) with three manufacturer entries — two
speakers and one subwoofer — matching the annotation types that
authority version makes attachable.

It exists so the catalog import path can be exercised end-to-end in
tests and by hand:

- Tests load it from the repository (`EquipmentCatalogImportPathTests`)
  and drive the full inbound flow: `InboundDocumentRouter` schema sniff
  -> routing availability -> `HTDTEquipmentCatalogSnapshot` decode ->
  `HTDTEquipmentCatalogLibrary` store/activate/list.
- Manually: pick it through the app's document import (Files share or
  the Library import). While a capture is active it is stored for
  explicit activation; while idle it is stored and activated
  immediately, and then appears in the equipment-catalog picker.
