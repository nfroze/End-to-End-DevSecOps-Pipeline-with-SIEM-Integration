require('dotenv').config();
const express = require('express');
const cookieParser = require('cookie-parser'); // required for csurf
const csrf = require('csurf'); // CSRF middleware
const userRoutes = require('./routes/user');

const app = express();
app.use(express.static('public'));
app.use(express.json());
app.use(cookieParser());

const csrfProtection = csrf({ cookie: true });
app.use(csrfProtection);

const PORT = process.env.PORT || 3000;

app.get('/csrf-token', (req, res) => {
  res.json({ csrfToken: req.csrfToken() });
});

app.use('/user', userRoutes);

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK', timestamp: new Date() });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});