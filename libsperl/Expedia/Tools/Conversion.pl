#!/usr/bin/perl -w

# ________________________________________________________________
# EN-TETE PAR DEFAUT
use strict;
use Getopt::Long;
use Encode qw(encode decode);

my $string;
my $option;

GetOptions(
  'option=s',\$option,
  'string=s',\$string,
);

my $enc = 'utf-8';

$string = decode($enc, $string);

if(!$option)
{
  $option='';
}

if($string)
{

	if($option eq 'PAX')
	{
	  #  => Le & est converti en ' '. Les chiffres ne sont pas tolérés !
	  # Pas de chiffres + Euro ¤
	  $string =~ s/(\d+|¤)//ig;
	  $string =~ s/(!|"|#|$|%|&|'|\(|\)|\*|\+|,|-|\.|\/|:|;|<|=|>|\?|@|\[|\\|\]|^|_|`|¡|¢|£|¥|§|©|ª|«|¬|®|¯|°|±|²|³|µ|¶|¹|º|»|¿|×|÷|\|)/ /ig;
	}
	elsif($option eq 'COMP')
	{
	#  => Le & est converti en ' '.
	#  #  => Les chiffres sont tolérés.
	  $string =~ s/(!|"|#|$|%|&|'|\(|\)|\*|\+|,|-|\.|\/|:|;|<|=|>|\?|@|\[|\\|\]|^|_|`|¡|¢|£|¥|§|©|ª|«|¬|®|¯|°|±|²|³|µ|¶|¹|º|»|¿|×|÷|\|)/ /ig;
	}
	else
	{
	#  => Chiffres tolérés.
	#  => Le & est converti en '&amp;'.
	#  => Les caractères - @ sont tolérés.
	  $string =~ s/(!|"|#|$|%|'|\(|\)|\*|\+|,|\.|\/|:|;|<|=|>|\?|\[|\\|\]|^|_|`|¡|¢|£|¥|§|©|ª|«|¬|®|¯|°|±|²|³|µ|¶|¹|º|»|¿|×|÷|\|)/ /ig;
	  $string =~ s/&/&amp;/ig;              # Conversion du &
	}

  $string =~ s/(Ą|Ā|Ă|Ã|Â|À|Á|â|à|á|ã|ă|ā|ą|a)/A/ig;
  $string =~ s/b/B/ig;
  $string =~ s/(Ç|Ċ|Č|Ĉ|Ć|ç|ć|ĉ|č|ċ|c)/C/ig;
  $string =~ s/(Ď|Đ|đ|ď|d)/D/ig;
  $string =~ s/(Ĕ|Ę|Ē|Ė|Ě|Ë|Ê|È|É|ë|ê|è|é|ě|ė|ē|ę|ĕ|e)/E/ig;
  $string =~ s/f/F/ig;
  $string =~ s/(Ģ|Ġ|Ğ|Ĝ|ĝ|ğ|ġ|ģ|g)/G/ig;
  $string =~ s/(Ĥ|Ħ|ħ|ĥ|h)/H/ig;
  $string =~ s/(Į|Ĭ|Ī|Ĩ|İ|Ï|Î|Ì|Í|ï|î|ì|í|ı|ĩ|ī|ĭ|į|i)/I/ig;
  $string =~ s/(Ĵ|ĵ|j)/J/ig;
  $string =~ s/(Ķ|ķ|k)/K/ig;
  $string =~ s/(Ł|Ĺ|Ľ|Ļ|Ŀ|ł|ĺ|ľ|ļ|ŀ|l)/L/ig;
  $string =~ s/m/M/ig;
  $string =~ s/(Ñ|Ń|Ň|Ņ|Ŋ|ń|ň|ņ|ŋ|ñ|n)/N/ig;
  $string =~ s/(Ŏ|Ō|Ő|Õ|Ô|Ò|Ó|ô|ò|ó|õ|ő|ō|ŏ|o)/O/ig;
  $string =~ s/p/P/ig;
  $string =~ s/q/Q/ig;
  $string =~ s/(Ř|Ŕ|Ŗ|ŕ|ŗ|ř|r)/R/ig;
  $string =~ s/(Ś|Ŝ|Ş|Š|ś|ŝ|ş|š|s)/S/ig;
  $string =~ s/(Ŧ|Ť|Ţ|ŧ|ť|ţ|t)/T/ig;
  $string =~ s/(Ų|Ū|Ů|Ű|Ŭ|Ũ|Û|Ù|Ú|û|ù|ú|ũ|ŭ|ű|ů|ū|u)/U/ig;
  $string =~ s/v/V/ig;
  $string =~ s/(Ŵ|ŵ|w)/W/ig;
  $string =~ s/x/X/ig;
  $string =~ s/(Ÿ|Ŷ|ý|Ý|ŷ|y)/Y/ig;
  $string =~ s/(Ž|Ź|ź|ž|Ż|ż|z)/Z/ig;
  $string =~ s/(æ|Æ)/AE/ig;
  $string =~ s/(½|¼)/OE/ig;
  $string =~ s/(\x{df}|ß)/SS/ig;
  $string =~ s/(Ü|ü)/UE/ig ;
  $string =~ s/(Ö|ö)/OE/ig ;
  $string =~ s/(Ä|ä)/AE/ig ;
  $string =~ s/(Ø|ø)/OE/ig ;
  $string =~ s/(Œ|œ)/OE/ig ;
  $string =~ s/(Å|å)/AA/ig ;
  $string =~ s/(Þ|þ)/TH/ig ;
  $string =~ s/(Ĳ|ĳ)/IJ/ig ;
  $string =~ s/\s+/ /ig;                # Nettoyage des espacements
  $string =~ s/(^\s*|\s*$)//ig;         # Nettoyage des espacements
  
  #EGE-105388 
  $string =~ s/&AMP;/&amp;/ig; 
  
  $string = encode($enc, $string);

	printf $string;
}
