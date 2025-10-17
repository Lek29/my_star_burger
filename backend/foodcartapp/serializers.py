from django.db import transaction
from phonenumber_field.serializerfields import PhoneNumberField
from rest_framework import serializers

from geocoordinates.utils import get_or_create_geocoded_address
from .models import Order, OrderItem, Product


class OrderItemSerializer(serializers.Serializer):
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.all())
    quantity = serializers.IntegerField(min_value=1)


class OrderSerializer(serializers.ModelSerializer):
    firstname = serializers.CharField(max_length=100, source='client_name')
    lastname = serializers.CharField(max_length=100, source='surname')
    phonenumber = PhoneNumberField(region='RU', source='phone')
    address = serializers.CharField(max_length=255, source='delivery_address')
    products = OrderItemSerializer(many=True, allow_empty=False, write_only=True)

    class Meta:
        model = Order
        fields = [
            'id',
            'firstname',
            'lastname',
            'phonenumber',
            'address',
            'products',
        ]

    def create(self, validated_data):
        order_items_payload = validated_data.pop('products')

        delivery_address_str = validated_data['delivery_address']
        geocoded_address_obj = get_or_create_geocoded_address(delivery_address_str)

        validated_data['geocoded_delivery_address'] = geocoded_address_obj

        with transaction.atomic():
            order_instance = super().create(validated_data)

            order_items_to_create = []
            for item_payload in order_items_payload:
                product_object = item_payload['product']
                quantity_value = item_payload['quantity']


                order_item = OrderItem(
                    order=order_instance,
                    product=product_object,
                    quantity=quantity_value,
                    price_at_purchase=product_object.price
                )

                order_items_to_create.append(order_item)

            OrderItem.objects.bulk_create(order_items_to_create)

        return order_instance
