const express = require('express');
const router = express.Router();

router.get('/', (req, res) => {
  res.json({ id: 1, username: "devsecops_demo" });
});

module.exports = router;