CREATE TABLE `domains` (
  `id` integer primary key AUTOINCREMENT,
  `id_base` int(11) ,
  `name` char(80) NOT NULL,
  `created` int(1) NOT NULL DEFAULT '0',
  `error` varchar(200) DEFAULT NULL,
  `uri` varchar(250) DEFAULT NULL,
  `is_base` int(1) NOT NULL DEFAULT '0',
  `file_base_img` varchar(255) DEFAULT NULL,
  `id_owner` int(11) NOT NULL,
  `vm` char(120) NOT NULL,
  `id_farm` integer,
  UNIQUE (`id_base`,`name`),
  UNIQUE (`name`)
);
