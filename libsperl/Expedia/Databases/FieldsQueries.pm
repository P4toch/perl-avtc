package Expedia::Databases::FieldsQueries;
# ----------------------------------------------------------------
# package Expedia::DB::FieldsQueries
#
# $Id: FieldsQueries.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
# ----------------------------------------------------------------

use Exporter 'import';

@EXPORT_OK = qw(&getFieldValue &insertIntoFields &updateFieldValue);

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération de la VALUE d'1 field
sub getFieldValue {
  my $params  = shift;
  
  my $key     = $params->{KEY};
  my $code    = $params->{CODE};
  my $subCode = $params->{SUBCODE} || '_';
  
  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $query   = '
    SELECT VALUE FROM FIELDS
    WHERE KEY     = ?
      AND CODE    = ?
      AND SUBCODE = ? ';
  
  my $res     = $dbh->saarBind($query, [$key, $code, $subCode]);
  
  return $res->[0][0] || undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un nouveau Field
sub insertIntoFields {
  my $params  = shift;
  
  my $key     = $params->{KEY};
  my $code    = $params->{CODE};
  my $value   = $params->{VALUE};
  my $subCode = $params->{SUBCODE} || '_';
  my $id      = _getFieldsSeqNextVal();
  
  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $query   = 'INSERT INTO FIELDS (ID, KEY, CODE, VALUE, SUBCODE) VALUES (?, ?, ? , ?, ?)';
  
  my $rows    = $dbh->doBind($query, [$id, $key, $code, $value, $subCode]);
  
  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour d'une VALUE d'un FIELDS
sub updateFieldValue {
  my $params  = shift;
  
  my $key     = $params->{KEY};
  my $code    = $params->{CODE};
  my $value   = $params->{VALUE};
  my $subCode = $params->{SUBCODE} || '_';
  
  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $query   = '
    UPDATE FIELDS
       SET VALUE   = ?
     WHERE [KEY]     = ?
       AND CODE    = ?
       AND SUBCODE = ? ';
  
  my $rows    = $dbh->doBind($query, [$value, $key, $code, $subCode]);
  
  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du prochain numéro de séquence de FIELDS.
sub _getFieldsSeqNextVal {
  my $dbh = $cnxMgr->getConnectionByName('mid');
  return $dbh->saar('SELECT FIELDS_SEQ.nextval FROM DUAL')->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
