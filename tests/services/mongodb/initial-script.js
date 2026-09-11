db.getSiblingDB("fixture").initialization.updateOne(
  {_id: "native-initial-script"}, {$inc: {runs: 1}}, {upsert: true}
);
