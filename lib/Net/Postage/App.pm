package Net::Postage::App;

use strict;
use warnings;
use JSON;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use MIME::Base64;
use File::Spec;
use Digest::SHA qw(sha1_hex);

our $VERSION = '0.03';

sub new {
    my ($class,%args) = @_;
    my $args = \%args;
    my $self = {};
    $self->{data}->{api_key} = $args->{api_key};
    $self->{json} = JSON->new;
    $self->{url} = $args->{url} || "http://api.postageapp.com/v.1.0/send_message.json";
    $self->{ua} = LWP::UserAgent->new(agent => 'Net-Postage-App ' . $VERSION);
    die 'api_key argument is required' if !$self->{data}->{api_key};
    return bless $self, $class;
}

sub message {
    my ($self,%msg) = @_;
    my $message = \%msg;
    my $subject = $message->{subject} || die 'subject argument is required';
    my $from = $message->{from} || die 'from argument is required';
    my $reply_to = $message->{reply_to};
    my $text = $message->{textmessage};
    my $html = $message->{htmlmessage};
    my $template = $message->{template};
    my $variables = $message->{variables};
    my $extra_headers = $message->{headers};
    if (!$text && !$html && !$template){
        die 'You have to include (textmessage and/or htmlmessage) or a predefined template';
    }
    
    ##generate uuid
    if ($message->{resend}) {
        $self->{data}->{uid} = sha1_hex($subject . ($text ? $text : '') . ($html ? $html : '') . time());
    }
    
    #do we have attachments
    if (my $attachments = $message->{attachments}) {
        my @attachments;
        foreach my $file (@{$attachments}){
            my $hash = {};
            my ($vol,$dir,$filename) = File::Spec->splitpath( $file );
            ##get file content
            open(my $fh, '<', $file) or die "can't open file $file $!";
            my $content = do {local $/; <$fh>};
            close $fh;
            
            $self->{data}->{arguments}->{attachments}->{$filename} = {
                'content_type' => 'application/octet-stream',
                'content' => encode_base64($content)
            };
        }
    }
    
    ###combine arguments
    $self->{data}->{arguments}->{content}->{'text/plain'} = $text if $text;
    $self->{data}->{arguments}->{content}->{'text/html'} = $html if $html;
    $self->{data}->{arguments}->{'template'} = $template if $template;
    $self->{data}->{arguments}->{'variables'} = $variables if $variables;
    $self->{data}->{arguments}->{headers} = {
        "subject" => $subject,
        "from" => $from,
        "reply-to" => $reply_to
    };
    
    while( my ($key, $value) = each %$extra_headers ) {
        $self->{data}->{arguments}->{headers}->{$key} = $value;
    }
    
    return $self->{data};
}

sub to {
    my ($self,$rec) = @_;
    my %all_rec = ();
    my %hash = ();
    if (ref $rec ){    
        if (ref $rec eq 'HASH'){
            %hash = %{$rec};
        } elsif (ref $rec eq 'ARRAY'){
            %hash = map { $_ => 1 } @{$rec};
        }
        
        if ($self->{data}->{arguments}->{recipients}){
            %all_rec = (%hash, %{$self->{data}->{arguments}->{recipients}});
        } else {
            %all_rec = %hash;
        }
        $self->{data}->{arguments}->{recipients} = \%all_rec;
    } else{
        $self->{data}->{arguments}->{recipients}->{$rec} = 1;
    }
    
    return $self->{data};
}

sub send {
    my $self = shift;
    my $json = $self->{json};
    my $data = $json->encode($self->{data});
    my $ua = $self->{ua};
    my $url = $self->{url};
    my $req = $ua->post(
        $url,
        'Content-Type' => 'application/json; charset=utf8',
        'Content'      => $data
    );
    
    my $response = $json->decode($req->content);
    $self->{data} = {};
    $self->{response} = $response;
}

sub response {
    shift->{response};
}

sub is_success {
    my $self = shift;
    if ($self->response->{response}->{status} eq "ok"){
        return 1;
    } else {
        return 0;
    }
}

sub errorMessage {
    shift->response->{response}->{message};
}

1;

__END__

=head1 NAME

Net::Postage::App - Perl extension for Postageapp.com API

=head1 SYNOPSIS

    use Net::Postage::App;  
    
    my $postage = Net::Postage::App->new(api_key => 'YOUR_PostageApp_API_KEY_HERE');
    
    ## first - prepare your message
    $postage->message(
        from => 'your_name <your_email>',
        subject => 'Hi This is a test message',
        textmessage => 'Hi there this is a TEXT message test',
        htmlmessage => '<b>Hi there this is an HTML message test</b>',
        reply_to => 'no-reply@example.com',
        headers => {
            'x-mailer' => 'Postage-App.pm'
        }
    );
    
    ## second - add recipients
    ## You can add a single recipient
    $postage->to('test@example.com');
    
    ## You can add an array of recipients at once
    $postage->to(['test@example.com','test2@example2.com',...]);
    
    ## Or hash of recipients for variable replacement
    $postage->to({
        'test@example.com' => { first_name => 'Mahmoud', ... },
        'test2@example2.com' => { first_name => 'fName', ... }
    });
    
    ## Last, do the send
    $postage->send();
    
    ## make sure the sending was suucessful
    ## otherwise send again later
    if (!$postage->is_success){
        print $postage->errorMessage . "\n";
    } else {
        print "Your message sent successfully";
    }

=head1 DESCRIPTION

Perl interface to the Postageapp.com API

postageapp.com "From their website" Outsource the sending of your application generated email,
so your app can do what it does best... be awesome!

See L<http://postageapp.com>

=head1 METHODS

=head2 new()

    my $postageapp = Net::Postage::App->new( api_key => 'YOUR API KEY' )

=head2 message()

Create a new message to be sebt later

    $postageapp->message(
        from => 'Joe <joe.something@domain.com>',
        subject => '...',
        textmessage => '...'
    )

message method accepts the following arguments

=over 4

=item from => 'name <emailAddress>'

Required : your from name and email address

=item subject => 'some text for subject'

Required : your message subject line

=item textmessage => 'text version of your email'

Optional if htmlmessage available

=item htmlmessage => 'html version of your message'

Optional if textmessage available, you can provide both fields

=item reply_to => 'reply_to email address'

Optional : reply to email field

=item attachments => ['/path/to/your/attachment.pdf']

arrayref of files you want to send as an attachment

=item resend => 1

Optional : When sending a message, a unique hash will be created to prevent resending
the same message again, set this to 1 if you want to send the same identical message to
same recipients

=item template => 'Template name'

Optional : name of the template you set at your postageapp dashboard
if you set this then there is no need for other headers

=item variables => { var1 => 'default text', .. }

Optional : hashref of default variables to be used when recipients info is missing

=item headers => { 'x-sender' => '...' }

Optional : hashref of extra headers to include in your email

=back

=head2 to()

Where to send your email

C<to> method accepts one of the following

=over 4

=item scalar

a single email address

    $postageapp->to('email address');

=item arrayref

an arrayref of multi recipients

    $postageapp->to(['email1','email2','...']);

=item hashref

hashref of multi recipients with customization fields

    {
        'email1' => {
            'name' => 'Joe',
            'age' => 32,
            ...
        },
        'email2' => {
            'name' => '',
            ...
        }
    }

to use these fields in your email you need to compose a text/html message in C<message> method
by wrapping a word in doubled curly braces like {{name}} and {{age}}

=back

=head2 send

send your email

    $postageapp->send()

=head2 is_success

returns true if the send process was successful

    if ( $postageapp->is_success ) {  }

=head2 errorMessage

returns error message if the send process failed

    $postageapp->errorMessage()

=head2 EXPORT

None by default.

=head1 SEE ALSO

For more information about postageapp API please visit their documentation page
http://postageapp.com/docs/api

=head1 AUTHOR

Mahmoud A Mehyar, E<lt>mamod.mehyar@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 by Mahmoud A. Mehyar

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
