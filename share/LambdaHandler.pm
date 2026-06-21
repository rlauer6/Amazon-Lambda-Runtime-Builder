########################################################################
package Event::SQS;
########################################################################

use strict;
use warnings;

use Data::Dumper;

use parent qw(Amazon::Lambda::Runtime::Event::SQS);

########################################################################
sub on_message {
########################################################################
  my ( $self, $body, $sqs_record ) = @_;

  my $logger = $self->get_logger;

  $logger->info('handling SQS event');

  $logger->info( Dumper( [ body => $body, sqs_record => $sqs_record ] ) );

  return;
}

########################################################################
package Event::SNS;
########################################################################

use strict;
use warnings;

use Data::Dumper;

use parent qw(Amazon::Lambda::Runtime::Event::SNS);

########################################################################
sub on_notification {
########################################################################
  my ( $self, $message, $sns, $sns_record ) = @_;

  my $logger = $self->get_logger;

  $logger->info('handling SNS event');

  $logger->info(
    Dumper(
      [ message => $message,
        topic   => $sns->{TopicArn},
        subject => $sns->{Subject},
      ]
    )
  );

  return;
}

########################################################################
package Event::S3;
########################################################################

use strict;
use warnings;

use Amazon::S3;
use Amazon::Credentials;
use Data::Dumper;
use English qw(-no_match_vars);
use List::Util qw(min);

use parent qw(Amazon::Lambda::Runtime::Event::S3);

my $s3;

########################################################################
sub get_s3 {
########################################################################
  return $s3 //= do {
    my $creds = Amazon::Credentials->new;
    Amazon::S3->new(
      credentials => $creds,
      region      => $ENV{AWS_REGION},
    );
  };
}

########################################################################
sub on_s3_event {
########################################################################
  my ( $self, $s3_record ) = @_;

  my $logger = $self->get_logger;

  $logger->info('handling S3 event');

  my $s3_meta = $s3_record->{s3};

  my $bucket_name = $s3_meta->{bucket}{name};
  my ( $key, $size ) = @{ $s3_meta->{object} }{qw(key size)};

  $logger->info(
    Dumper(
      [ event_name => $s3_record->{eventName},
        bucket     => $bucket_name,
        key        => $key,
        size       => $size,
      ]
    )
  );

  my $bucket = get_s3()->bucket($bucket_name);

  my $response = eval { $bucket->get_key($key); };

  if ($EVAL_ERROR) {
    $logger->error( sprintf 'failed to read s3://%s/%s: %s', $bucket_name, $key, $EVAL_ERROR );
    return;
  }

  $logger->info( Dumper( [ response => $response ] ) );

  my $obj = $response->{value};

  my $obj_len = length $obj;

  $logger->info( sprintf 'read %d bytes from s3://%s/%s', $obj_len, $bucket_name, $key, );

  my $sample_len = min( 256, $obj_len );

  $logger->info( sprintf 'first %s bytes of %s', $sample_len, $obj_len );

  $logger->info( substr $obj, 0, $sample_len );

  return;
}

########################################################################
package Event::EventBridge;
########################################################################

use strict;
use warnings;

use Data::Dumper;

use parent qw(Amazon::Lambda::Runtime::Event::EventBridge);

########################################################################
sub on_event {
########################################################################
  my ( $self, $detail_type, $detail, $event ) = @_;

  my $logger = $self->get_logger;

  $logger->info('handling EventBridge event');

  $logger->info(
    Dumper(
      [ detail_type => $detail_type,
        source      => $event->{source},
        detail      => $detail,
      ]
    )
  );

  return;
}

########################################################################
package LambdaHandler;
########################################################################

use strict;
use warnings;

use parent qw(Amazon::Lambda::Runtime);

use Amazon::Lambda::Runtime::Event qw(:all);

__PACKAGE__->register_event_handler( $EVENT_SQS         => 'Event::SQS' );
__PACKAGE__->register_event_handler( $EVENT_SNS         => 'Event::SNS' );
__PACKAGE__->register_event_handler( $EVENT_S3          => 'Event::S3' );
__PACKAGE__->register_event_handler( $EVENT_EVENTBRIDGE => 'Event::EventBridge' );

sub handler {
  my ( $self, $event, $context ) = @_;

  # streaming test — only fires for Function URL invocations
  # which have no Records and no detail-type
  if ( !$event->{Records} && !$event->{'detail-type'} ) {
    return sub {
      my ($writer) = @_;
      $writer->write('{"chunk":1,"message":"Hello from streaming Perl Lambda!"}');
      $writer->write('{"chunk":2,"message":"Still streaming..."}');
      $writer->close;
    };
  }

  # delegate everything else to the base class registry dispatch
  return $self->SUPER::handler( $event, $context );
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 NAME

LambdaHandler - Example event handlers

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

Rob Lauer - <rlauer@treasurersbriefcase.com>

=cut
