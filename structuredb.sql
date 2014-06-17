CREATE DATABASE IF NOT EXISTS `limitsdir` DEFAULT CHARACTER SET latin1 COLLATE latin1_swedish_ci;

USE `limitsdir`;

DROP TABLE IF EXISTS `list`;
CREATE TABLE IF NOT EXISTS `list` (
  `name` varchar(255) NOT NULL,
  `web_size` int(11) NOT NULL,
  `db_size` int(11) NOT NULL,
  `exception` tinyint(1) NOT NULL,
  `blocked` tinyint(1) NOT NULL,
  `status` tinyint(4) NOT NULL,
  `date` date NOT NULL,
  PRIMARY KEY (`name`),
  UNIQUE KEY `name_2` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
